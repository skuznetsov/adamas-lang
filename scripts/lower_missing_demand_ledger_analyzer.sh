#!/usr/bin/env bash
# Bounded streaming analyzer for [LOWER_MISSING_LEDGER] rows.
#
# This tool is deliberately diagnostic. It validates the producer contract,
# keeps only bounded scalar distinct-ID state, and reports observations. It
# never infers a root cause or authorizes a materialization change.  The
# optional [MAT_DONE] join is an external observation; a demand outcome alone
# is not treated as proof that a body was created.
#
# Input is an immutable compiler-log snapshot captured after the producer has
# exited or been killed. The snapshot is rejected above a hard byte cap before
# Bash reads any line; live, concurrently growing files are outside this tool's
# contract.
set -euo pipefail
set -f
LC_ALL=C

if (( BASH_VERSINFO[0] < 4 )); then
  echo "ERROR: analyzer requires Bash 4 or newer" >&2
  exit 2
fi

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "usage: $0 <ledger-log>" >&2
  exit 2
fi

LOG="$1"
# One producer invocation emits at most 4096 demand rows.  The default accepts
# several invocations plus their summaries/checkpoints and historical
# materialization rows; callers can lower it for a bounded falsifier.
MAX_ROWS="${LOWER_MISSING_ANALYZER_MAX_ROWS:-131072}"
MAX_IDS="${LOWER_MISSING_ANALYZER_MAX_IDS:-32768}"
MAX_LOG_BYTES="${LOWER_MISSING_ANALYZER_MAX_LOG_BYTES:-67108864}"
HARD_MAX_ROWS=131072
HARD_MAX_IDS=32768
HARD_MAX_LOG_BYTES=67108864
INT32_MAX=2147483647

if [[ ! "$MAX_ROWS" =~ ^[1-9][0-9]{0,9}$ ||
      ! "$MAX_IDS" =~ ^[1-9][0-9]{0,9}$ ||
      ! "$MAX_LOG_BYTES" =~ ^[1-9][0-9]{0,9}$ ]]; then
  echo "ERROR: analyzer caps must be canonical positive integers" >&2
  exit 2
fi
if (( 10#$MAX_ROWS > HARD_MAX_ROWS ||
      10#$MAX_IDS > HARD_MAX_IDS ||
      10#$MAX_LOG_BYTES > HARD_MAX_LOG_BYTES )); then
  echo "ERROR: analyzer caps exceed hard bounds rows=${HARD_MAX_ROWS} ids=${HARD_MAX_IDS} bytes=${HARD_MAX_LOG_BYTES}" >&2
  exit 2
fi

log_bytes=""
if candidate="$(stat -f %z "$LOG" 2>/dev/null)" &&
   [[ "$candidate" =~ ^(0|[1-9][0-9]{0,9})$ ]]; then
  log_bytes="$candidate"
elif candidate="$(stat -c %s "$LOG" 2>/dev/null)" &&
     [[ "$candidate" =~ ^(0|[1-9][0-9]{0,9})$ ]]; then
  log_bytes="$candidate"
fi
if [[ -z "$log_bytes" ]]; then
  echo "ERROR: unable to determine input size" >&2
  exit 2
fi
if (( 10#$log_bytes > 10#$MAX_LOG_BYTES )); then
  echo "ERROR: input exceeds bounded analyzer size (${MAX_LOG_BYTES} bytes)" >&2
  exit 1
fi

rows=0
demand_rows=0
summary_rows=0
checkpoint_rows=0
mat_done_rows=0
malformed_rows=0
typed_handoff_rows=0
name_only_rows=0
materialized_rows=0
deferred_rows=0
still_missing_rows=0
skipped_rows=0
repeat_requested_ids=0
distinct_requested_ids=0
distinct_id_overflow=0
mat_done_distinct_ids=0
mat_done_id_overflow=0
mat_done_joined_requested_ids=0
mat_done_body_joined_requested_ids=0
summary_function_growth=0
summary_pending_growth=0
summary_overflow=0
summary_unfinished=0
summary_limit=0
summary_emitted=0
initial_summaries=0
final_summaries=0
incomplete_checkpoints=0
complete_checkpoints=0
stream_complete=0
shape_ambiguous_rows=0
shape_mismatch_observations=0
invocation_active=0
awaiting_summary=0
invocation_context=""
invocation_demand_rows=0
invocation_end_iteration=""

declare -A seen_requested=()
declare -A seen_mat_done=()
declare -A seen_mat_done_body=()

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_field() {
  local key="$1" value="$2"
  [[ -n "$value" ]] || {
    malformed_rows=$((malformed_rows + 1))
    fail "missing field ${key}"
  }
}

is_count() {
  [[ "$1" =~ ^(0|[1-9][0-9]{0,9})$ ]] && (( 10#$1 <= INT32_MAX ))
}

is_uint64() {
  local value="$1"
  [[ "$value" =~ ^(0|[1-9][0-9]*)$ ]] || return 1
  (( ${#value} < 20 )) && return 0
  (( ${#value} == 20 )) || return 1
  [[ "$value" == "18446744073709551615" || "$value" < "18446744073709551615" ]]
}

is_hex_u64() {
  [[ "$1" =~ ^0x(0|[1-9a-f][0-9a-f]{0,15})$ ]]
}

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "[MAT_DONE]"* ]]; then
    rows=$((rows + 1))
    (( rows <= MAX_ROWS )) || fail "row cap exceeded (${MAX_ROWS})"
    mat_done_rows=$((mat_done_rows + 1))

    requested_id=""
    has_body=""
    declare -A row_fields=()
    for field in ${line#"[MAT_DONE] "}; do
      [[ "$field" == *=* ]] || fail "malformed MAT_DONE token"
      key="${field%%=*}"
      value="${field#*=}"
      [[ "$key" =~ ^[a-z_][a-z0-9_]*$ ]] || fail "invalid MAT_DONE key"
      [[ ! -v "row_fields[$key]" ]] || fail "duplicate MAT_DONE field ${key}"
      row_fields["$key"]=1
      case "$key" in
        requested_id) requested_id="$value" ;;
        has_body) has_body="$value" ;;
      esac
    done
    require_field requested_id "$requested_id"
    require_field has_body "$has_body"
    is_hex_u64 "$requested_id" || fail "non-uint64 MAT_DONE requested_id"
    [[ "$has_body" == 0 || "$has_body" == 1 ]] || fail "invalid MAT_DONE has_body=${has_body}"

    if [[ -v "seen_mat_done[$requested_id]" ]]; then
      if [[ "$has_body" == 1 ]]; then
        seen_mat_done_body["$requested_id"]=1
      fi
    elif (( mat_done_distinct_ids < MAX_IDS )); then
      seen_mat_done["$requested_id"]=1
      mat_done_distinct_ids=$((mat_done_distinct_ids + 1))
      if [[ "$has_body" == 1 ]]; then
        seen_mat_done_body["$requested_id"]=1
      fi
    else
      mat_done_id_overflow=$((mat_done_id_overflow + 1))
    fi
    continue
  fi

  [[ "$line" == "[LOWER_MISSING_LEDGER]"* ]] || continue

  rows=$((rows + 1))
  (( rows <= MAX_ROWS )) || fail "row cap exceeded (${MAX_ROWS})"

  schema=""
  event=""
  seq=""
  iteration=""
  context=""
  reason=""
  owner_kind=""
  owner_id=""
  requested_id=""
  materialized_id=""
  enqueue=""
  outcome=""
  handoff=""
  resolution_id=""
  callsite_arena_id=""
  callsite_expr_id=""
  def_arena_id=""
  def_expr_id=""
  receiver_type_id=""
  arg_count=""
  block_type_id=""
  function_count_before=""
  function_count_after=""
  pending_before=""
  pending_after=""
  shape_id=""
  shape_mismatch_count=""
  shape_ambiguous=""
  emitted=""
  overflow=""
  unfinished=""
  limit=""
  function_count_start=""
  function_count_end=""
  pending_start=""
  pending_end=""
  complete=""

  declare -A row_fields=()
  for field in ${line#"[LOWER_MISSING_LEDGER] "}; do
    [[ "$field" == *=* ]] || fail "malformed ledger token"
    key="${field%%=*}"
    value="${field#*=}"
    [[ "$key" =~ ^[a-z_][a-z0-9_]*$ ]] || fail "invalid ledger key"
    [[ ! -v "row_fields[$key]" ]] || fail "duplicate ledger field ${key}"
    row_fields["$key"]=1
    case "$key" in
      schema) schema="$value" ;;
      event) event="$value" ;;
      seq) seq="$value" ;;
      iteration) iteration="$value" ;;
      context) context="$value" ;;
      reason) reason="$value" ;;
      owner_kind) owner_kind="$value" ;;
      owner_id) owner_id="$value" ;;
      requested_id) requested_id="$value" ;;
      materialized_id) materialized_id="$value" ;;
      enqueue) enqueue="$value" ;;
      outcome) outcome="$value" ;;
      handoff) handoff="$value" ;;
      resolution_id) resolution_id="$value" ;;
      callsite_arena_id) callsite_arena_id="$value" ;;
      callsite_expr_id) callsite_expr_id="$value" ;;
      def_arena_id) def_arena_id="$value" ;;
      def_expr_id) def_expr_id="$value" ;;
      receiver_type_id) receiver_type_id="$value" ;;
      arg_count) arg_count="$value" ;;
      block_type_id) block_type_id="$value" ;;
      function_count_before) function_count_before="$value" ;;
      function_count_after) function_count_after="$value" ;;
      pending_before) pending_before="$value" ;;
      pending_after) pending_after="$value" ;;
      hir_arg_shape_id) shape_id="$value" ;;
      shape_mismatch_count) shape_mismatch_count="$value" ;;
      shape_ambiguous) shape_ambiguous="$value" ;;
      emitted) emitted="$value" ;;
      overflow) overflow="$value" ;;
      unfinished) unfinished="$value" ;;
      limit) limit="$value" ;;
      function_count_start) function_count_start="$value" ;;
      function_count_end) function_count_end="$value" ;;
      pending_start) pending_start="$value" ;;
      pending_end) pending_end="$value" ;;
      complete) complete="$value" ;;
      *) fail "unknown ledger field ${key}" ;;
    esac
  done

  [[ "$schema" == "lower_missing_demand_v1" ]] || fail "unexpected schema: ${schema:-<missing>}"
  case "$event" in
    demand)
      for key in "${!row_fields[@]}"; do
        case "$key" in
          schema|event|seq|iteration|context|reason|owner_kind|owner_id|requested_id|materialized_id|enqueue|outcome|handoff|resolution_id|callsite_arena_id|callsite_expr_id|def_arena_id|def_expr_id|receiver_type_id|arg_count|block_type_id|function_count_before|function_count_after|pending_before|pending_after|hir_arg_shape_id|shape_mismatch_count|shape_ambiguous) ;;
          *) fail "field ${key} is invalid for demand event" ;;
        esac
      done
      (( invocation_active == 1 )) || fail "demand outside active invocation"
      demand_rows=$((demand_rows + 1))
      require_field seq "$seq"
      require_field iteration "$iteration"
      require_field context "$context"
      require_field reason "$reason"
      require_field owner_kind "$owner_kind"
      require_field owner_id "$owner_id"
      require_field requested_id "$requested_id"
      require_field materialized_id "$materialized_id"
      require_field enqueue "$enqueue"
      require_field outcome "$outcome"
      require_field handoff "$handoff"
      require_field function_count_before "$function_count_before"
      require_field function_count_after "$function_count_after"
      require_field pending_before "$pending_before"
      require_field pending_after "$pending_after"
      require_field hir_arg_shape_id "$shape_id"
      require_field shape_mismatch_count "$shape_mismatch_count"
      require_field shape_ambiguous "$shape_ambiguous"
      is_uint64 "$seq" || fail "invalid uint64 seq"
      is_count "$iteration" || fail "out-of-range iteration"
      is_hex_u64 "$owner_id" || fail "invalid uint64 owner_id"
      is_hex_u64 "$requested_id" || fail "invalid uint64 requested_id"
      is_hex_u64 "$materialized_id" || fail "invalid uint64 materialized_id"
      is_hex_u64 "$shape_id" || fail "invalid uint64 hir_arg_shape_id"
      is_count "$function_count_before" || fail "out-of-range function_count_before"
      is_count "$function_count_after" || fail "out-of-range function_count_after"
      is_count "$pending_before" || fail "out-of-range pending_before"
      is_count "$pending_after" || fail "out-of-range pending_after"
      is_count "$shape_mismatch_count" || fail "out-of-range shape_mismatch_count"
      [[ "$context" == "$invocation_context" ]] || fail "demand context differs from invocation"
      [[ "$seq" == "$invocation_demand_rows" ]] || fail "non-contiguous demand seq"
      [[ "$enqueue" == 1 ]] || fail "demand row without enqueue=1"
      [[ "$shape_ambiguous" == 0 || "$shape_ambiguous" == 1 ]] || fail "invalid shape_ambiguous"
      [[ "$function_count_after" -ge "$function_count_before" ]] || fail "function count regressed"
      case "$context" in
        initial|final) ;;
        *) fail "unknown demand context=${context}" ;;
      esac
      case "$reason" in
        call_target|super_alias|super_target|module_fallback) ;;
        *) fail "unknown demand reason=${reason}" ;;
      esac
      case "$owner_kind" in
        top_level|instance|class|unknown) ;;
        *) fail "unknown owner_kind=${owner_kind}" ;;
      esac
      if [[ "$shape_ambiguous" == 1 ]]; then
        (( shape_mismatch_count > 0 )) || fail "ambiguous shape without mismatches"
      else
        (( shape_mismatch_count == 0 )) || fail "shape mismatches without ambiguity"
      fi

      if [[ -v "seen_requested[$requested_id]" ]]; then
        repeat_requested_ids=$((repeat_requested_ids + 1))
      elif (( distinct_requested_ids < MAX_IDS )); then
        seen_requested["$requested_id"]=1
        distinct_requested_ids=$((distinct_requested_ids + 1))
      else
        distinct_id_overflow=$((distinct_id_overflow + 1))
      fi

      if [[ "$handoff" == 1 ]]; then
        typed_handoff_rows=$((typed_handoff_rows + 1))
        is_uint64 "$resolution_id" || fail "typed handoff missing uint64 resolution_id"
        is_hex_u64 "$callsite_arena_id" || fail "typed handoff missing uint64 callsite_arena_id"
        is_count "$callsite_expr_id" || fail "typed handoff missing int32 callsite_expr_id"
        is_hex_u64 "$def_arena_id" || fail "typed handoff missing uint64 def_arena_id"
        is_count "$def_expr_id" || fail "typed handoff missing int32 def_expr_id"
        is_uint64 "$receiver_type_id" || fail "typed handoff missing uint64 receiver_type_id"
        is_count "$arg_count" || fail "typed handoff missing int32 arg_count"
        is_uint64 "$block_type_id" || fail "typed handoff missing uint64 block_type_id"
      elif [[ "$handoff" == 0 ]]; then
        name_only_rows=$((name_only_rows + 1))
        [[ "$resolution_id" == 0 ]] || fail "name-only row has resolution_id"
        [[ "$callsite_arena_id" == 0 && "$callsite_expr_id" == -1 ]] || fail "name-only row has callsite identity"
        [[ "$def_arena_id" == 0 && "$def_expr_id" == -1 ]] || fail "name-only row has def identity"
        [[ "$receiver_type_id" == 0 && "$arg_count" == 0 && "$block_type_id" == 0 ]] || fail "name-only row has semantic type identity"
      else
        fail "invalid handoff=${handoff}"
      fi

      case "$outcome" in
        materialized)
          materialized_rows=$((materialized_rows + 1))
          [[ "$materialized_id" != 0x0 ]] || fail "materialized row has zero materialized_id"
          ;;
        deferred) deferred_rows=$((deferred_rows + 1)) ;;
        still_missing) still_missing_rows=$((still_missing_rows + 1)) ;;
        skipped) skipped_rows=$((skipped_rows + 1)) ;;
        *) fail "invalid outcome=${outcome}" ;;
      esac
      if [[ "$shape_ambiguous" == 1 ]]; then
        shape_ambiguous_rows=$((shape_ambiguous_rows + 1))
      fi
      shape_mismatch_observations=$((shape_mismatch_observations + shape_mismatch_count))
      invocation_demand_rows=$((invocation_demand_rows + 1))
      ;;
    summary)
      for key in "${!row_fields[@]}"; do
        case "$key" in
          schema|event|iteration|context|emitted|overflow|unfinished|limit|function_count_start|function_count_end|pending_start|pending_end|complete) ;;
          *) fail "field ${key} is invalid for summary event" ;;
        esac
      done
      (( invocation_active == 0 && awaiting_summary == 1 )) || fail "summary without completed invocation"
      summary_rows=$((summary_rows + 1))
      require_field iteration "$iteration"
      require_field context "$context"
      require_field emitted "$emitted"
      require_field overflow "$overflow"
      require_field unfinished "$unfinished"
      require_field limit "$limit"
      require_field function_count_start "$function_count_start"
      require_field function_count_end "$function_count_end"
      require_field pending_start "$pending_start"
      require_field pending_end "$pending_end"
      require_field complete "$complete"
      is_count "$iteration" || fail "out-of-range summary iteration"
      is_count "$emitted" || fail "out-of-range summary emitted"
      is_count "$overflow" || fail "out-of-range summary overflow"
      is_count "$unfinished" || fail "out-of-range summary unfinished"
      is_count "$limit" || fail "out-of-range summary limit"
      is_count "$function_count_start" || fail "out-of-range function_count_start"
      is_count "$function_count_end" || fail "out-of-range function_count_end"
      is_count "$pending_start" || fail "out-of-range pending_start"
      is_count "$pending_end" || fail "out-of-range pending_end"
      [[ "$complete" == 1 ]] || fail "summary must be complete"
      [[ "$context" == "$invocation_context" ]] || fail "summary context differs from invocation"
      [[ "$iteration" == "$invocation_end_iteration" ]] || fail "summary iteration differs from completion checkpoint"
      [[ "$emitted" == "$invocation_demand_rows" ]] || fail "summary emitted differs from demand row count"
      [[ "$unfinished" == 0 ]] || fail "complete summary has unfinished rows"
      (( limit > 0 )) || fail "summary limit must be positive"
      (( limit <= 65536 )) || fail "summary limit exceeds producer hard cap"
      [[ "$emitted" -le "$limit" ]] || fail "summary emitted exceeds limit"
      [[ "$function_count_end" -ge "$function_count_start" ]] || fail "summary function count regressed"
      summary_emitted=$((summary_emitted + emitted))
      summary_overflow=$((summary_overflow + overflow))
      summary_unfinished=$((summary_unfinished + unfinished))
      summary_limit=$((summary_limit + limit))
      summary_function_growth=$((summary_function_growth + function_count_end - function_count_start))
      summary_pending_growth=$((summary_pending_growth + pending_end - pending_start))
      if [[ "$complete" == 1 ]]; then
        stream_complete=1
      else
        stream_complete=0
      fi
      case "$context" in
        initial) initial_summaries=$((initial_summaries + 1)) ;;
        final) final_summaries=$((final_summaries + 1)) ;;
        *) fail "unknown summary context=${context}" ;;
      esac
      awaiting_summary=0
      ;;
    checkpoint)
      for key in "${!row_fields[@]}"; do
        case "$key" in
          schema|event|iteration|context|complete) ;;
          *) fail "field ${key} is invalid for checkpoint event" ;;
        esac
      done
      checkpoint_rows=$((checkpoint_rows + 1))
      require_field iteration "$iteration"
      require_field context "$context"
      require_field complete "$complete"
      is_count "$iteration" || fail "out-of-range checkpoint iteration"
      [[ "$complete" == 0 || "$complete" == 1 ]] || fail "invalid checkpoint complete=${complete}"
      case "$context" in
        initial|final) ;;
        *) fail "unknown checkpoint context=${context}" ;;
      esac
      if [[ "$complete" == 1 ]]; then
        (( invocation_active == 1 )) || fail "completion checkpoint without active invocation"
        [[ "$context" == "$invocation_context" ]] || fail "completion context differs from invocation"
        complete_checkpoints=$((complete_checkpoints + 1))
        invocation_active=0
        awaiting_summary=1
        invocation_end_iteration="$iteration"
        stream_complete=0
      else
        (( invocation_active == 0 && awaiting_summary == 0 )) || fail "nested ledger invocation"
        [[ "$iteration" == 0 ]] || fail "start checkpoint iteration must be zero"
        incomplete_checkpoints=$((incomplete_checkpoints + 1))
        invocation_active=1
        invocation_context="$context"
        invocation_demand_rows=0
        invocation_end_iteration=""
        stream_complete=0
      fi
      ;;
    *)
      malformed_rows=$((malformed_rows + 1))
      fail "unknown event=${event:-<missing>}"
      ;;
  esac
done < "$LOG"

if (( invocation_active == 1 || awaiting_summary == 1 )); then
  stream_complete=0
fi

(( checkpoint_rows > 0 )) || fail "no checkpoint rows"
if (( summary_rows == 0 && incomplete_checkpoints == 0 )); then
  fail "no summary rows or incomplete checkpoint"
fi
(( malformed_rows == 0 )) || fail "malformed rows=${malformed_rows}"

# Join after the stream has been consumed so [MAT_DONE] may precede or follow
# its corresponding demand.  Only bounded IDs are considered; overflow is
# reported rather than silently treated as a complete join.
for requested_id in "${!seen_requested[@]}"; do
  if [[ -v "seen_mat_done[$requested_id]" ]]; then
    mat_done_joined_requested_ids=$((mat_done_joined_requested_ids + 1))
  fi
  if [[ -v "seen_mat_done_body[$requested_id]" ]]; then
    mat_done_body_joined_requested_ids=$((mat_done_body_joined_requested_ids + 1))
  fi
done

printf 'lower_missing_demand_receipt_v1 rows=%d demand_rows=%d summaries=%d checkpoints=%d mat_done_rows=%d typed_handoff=%d name_only=%d materialized=%d deferred=%d still_missing=%d skipped=%d repeated_requested_ids=%d distinct_requested_ids=%d distinct_id_overflow=%d mat_done_distinct_ids=%d mat_done_id_overflow=%d mat_done_joined_requested_ids=%d mat_done_body_joined_requested_ids=%d shape_ambiguous_rows=%d shape_mismatch_observations=%d function_growth=%d pending_growth=%d summary_emitted=%d summary_overflow=%d summary_unfinished=%d summary_limit=%d initial_summaries=%d final_summaries=%d incomplete_checkpoints=%d complete_checkpoints=%d stream_complete=%d identity=fnv1a64_telemetry collision_check=absent root_cause=unclassified\n' \
  "$rows" "$demand_rows" "$summary_rows" "$checkpoint_rows" "$mat_done_rows" \
  "$typed_handoff_rows" "$name_only_rows" "$materialized_rows" "$deferred_rows" \
  "$still_missing_rows" "$skipped_rows" "$repeat_requested_ids" \
  "$distinct_requested_ids" "$distinct_id_overflow" "$mat_done_distinct_ids" \
  "$mat_done_id_overflow" "$mat_done_joined_requested_ids" \
  "$mat_done_body_joined_requested_ids" "$shape_ambiguous_rows" \
  "$shape_mismatch_observations" "$summary_function_growth" \
  "$summary_pending_growth" "$summary_emitted" "$summary_overflow" \
  "$summary_unfinished" "$summary_limit" "$initial_summaries" "$final_summaries" \
  "$incomplete_checkpoints" "$complete_checkpoints" "$stream_complete"
