#!/usr/bin/env bash
# Contract regression for the bounded lower_missing ledger analyzer.
#
# The fixtures exercise both complete and killed streams, malformed rows,
# bounded caps, order-independent MAT_DONE joining, and shape ambiguity.  No
# compiler binary is run here; the regression itself is invoked through
# scripts/run_safe.sh by its caller.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANALYZER="$ROOT_DIR/scripts/lower_missing_demand_ledger_analyzer.sh"
WORK_DIR="$(mktemp -d /private/tmp/adamas_lower_missing_analyzer.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ ! -f "$ANALYZER" ]]; then
  echo "missing analyzer: $ANALYZER" >&2
  exit 2
fi

checkpoint() {
  local iteration="$1" context="$2" complete="$3"
  printf '[LOWER_MISSING_LEDGER] schema=lower_missing_demand_v1 event=checkpoint iteration=%s context=%s complete=%s\n' \
    "$iteration" "$context" "$complete"
}

demand() {
  local id="$1" shape="$2" mismatch="$3" ambiguous="$4" outcome="$5" materialized_id="$6" seq="${7:-0}"
  printf '[LOWER_MISSING_LEDGER] schema=lower_missing_demand_v1 event=demand seq=%s iteration=0 context=initial reason=call_target owner_kind=top_level owner_id=0x0 requested_id=%s materialized_id=%s enqueue=1 function_count_before=1 function_count_after=2 pending_before=0 pending_after=1 hir_arg_shape_id=%s shape_mismatch_count=%s shape_ambiguous=%s outcome=%s handoff=0 resolution_id=0 callsite_arena_id=0 callsite_expr_id=-1 def_arena_id=0 def_expr_id=-1 receiver_type_id=0 arg_count=0 block_type_id=0\n' \
    "$seq" "$id" "$materialized_id" "$shape" "$mismatch" "$ambiguous" "$outcome"
}

typed_demand() {
  local id="$1" shape="$2" mismatch="$3" ambiguous="$4" outcome="$5" materialized_id="$6"
  printf '[LOWER_MISSING_LEDGER] schema=lower_missing_demand_v1 event=demand seq=0 iteration=0 context=initial reason=call_target owner_kind=top_level owner_id=0x0 requested_id=%s materialized_id=%s enqueue=1 function_count_before=1 function_count_after=2 pending_before=0 pending_after=1 hir_arg_shape_id=%s shape_mismatch_count=%s shape_ambiguous=%s outcome=%s handoff=1 resolution_id=1 callsite_arena_id=0x11 callsite_expr_id=2 def_arena_id=0x11 def_expr_id=3 receiver_type_id=4 arg_count=1 block_type_id=0\n' \
    "$id" "$materialized_id" "$shape" "$mismatch" "$ambiguous" "$outcome"
}

summary() {
  local iteration="$1" context="$2" complete="$3" emitted="${4:-2}"
  printf '[LOWER_MISSING_LEDGER] schema=lower_missing_demand_v1 event=summary iteration=%s context=%s emitted=%s overflow=0 unfinished=0 limit=4 function_count_start=1 function_count_end=2 pending_start=0 pending_end=1 complete=%s\n' \
    "$iteration" "$context" "$emitted" "$complete"
}

expect_success() {
  local label="$1" log="$2" expected="$3"
  local output
  if ! output="$(bash "$ANALYZER" "$log")"; then
    echo "FAIL[$label]: analyzer rejected a valid fixture" >&2
    exit 1
  fi
  for token in $expected; do
    if [[ "$output" != *"$token"* ]]; then
      echo "FAIL[$label]: missing receipt token $token" >&2
      echo "$output" >&2
      exit 1
    fi
  done
  echo "PASS[$label]: $output"
}

expect_failure() {
  local label="$1" log="$2"
  if bash "$ANALYZER" "$log" >"$WORK_DIR/$label.out" 2>&1; then
    echo "FAIL[$label]: malformed/capped fixture was accepted" >&2
    cat "$WORK_DIR/$label.out" >&2
    exit 1
  fi
  echo "PASS[$label]: rejected as expected"
}

# Complete stream. MAT_DONE intentionally precedes demand; the two rows share
# one ID and the second observation changes the HIR shape.
COMPLETE_LOG="$WORK_DIR/complete.log"
{
  printf '[MAT_DONE] requested=foo requested_id=0xabc target=foo materialized=foo has_function=1 has_body=1 state=completed status=completed_with_hir_body reason=materialized_body_present created_function_count=1 producer_path=test created_symbol_relation=created_exact_symbol created_symbols=foo\n'
  checkpoint 0 initial 0
  typed_demand 0xabc 0x1 0 0 materialized 0xabc
  demand 0xabc 0x2 1 1 deferred 0x0 1
  checkpoint 1 initial 1
  summary 1 initial 1 2
} >"$COMPLETE_LOG"
expect_success complete "$COMPLETE_LOG" \
  "mat_done_joined_requested_ids=1 mat_done_body_joined_requested_ids=1 shape_ambiguous_rows=1 shape_mismatch_observations=1 stream_complete=1"

# A later invocation starts and is killed before its final summary. The latest
# incomplete checkpoint must dominate the earlier completed invocation.
TIMEOUT_LOG="$WORK_DIR/timeout.log"
{
  checkpoint 0 initial 0
  checkpoint 1 initial 1
  summary 1 initial 1 0
  checkpoint 0 final 0
} >"$TIMEOUT_LOG"
expect_success later_timeout "$TIMEOUT_LOG" "initial_summaries=1 final_summaries=0 incomplete_checkpoints=2 stream_complete=0"

# Missing shape_mismatch_count is a producer-contract violation.
MALFORMED_LOG="$WORK_DIR/malformed.log"
{
  checkpoint 0 initial 0
  printf '[LOWER_MISSING_LEDGER] schema=lower_missing_demand_v1 event=demand seq=0 iteration=0 context=initial reason=call_target owner_kind=top_level owner_id=0x0 requested_id=0x1 materialized_id=0x0 enqueue=1 function_count_before=1 function_count_after=1 pending_before=0 pending_after=0 hir_arg_shape_id=0x1 shape_ambiguous=0 outcome=deferred handoff=0 resolution_id=0 callsite_arena_id=0 callsite_expr_id=-1 def_arena_id=0 def_expr_id=-1 receiver_type_id=0 arg_count=0 block_type_id=0\n'
} >"$MALFORMED_LOG"
expect_failure malformed "$MALFORMED_LOG"

# Stringly values outside the producer enums must fail closed.
BAD_ENUM_LOG="$WORK_DIR/bad_enum.log"
{
  checkpoint 0 initial 0
  printf '[LOWER_MISSING_LEDGER] schema=lower_missing_demand_v1 event=demand seq=0 iteration=0 context=bogus reason=bogus owner_kind=bogus owner_id=0x0 requested_id=0x1 materialized_id=0x0 enqueue=1 function_count_before=1 function_count_after=1 pending_before=0 pending_after=0 hir_arg_shape_id=0x1 shape_mismatch_count=0 shape_ambiguous=0 outcome=deferred handoff=0 resolution_id=0 callsite_arena_id=0 callsite_expr_id=-1 def_arena_id=0 def_expr_id=-1 receiver_type_id=0 arg_count=0 block_type_id=0\n'
} >"$BAD_ENUM_LOG"
expect_failure bad_enum "$BAD_ENUM_LOG"

# Typed handoff rows must carry their complete numeric identity projection.
BAD_HANDOFF_LOG="$WORK_DIR/bad_handoff.log"
{
  checkpoint 0 initial 0
  printf '[LOWER_MISSING_LEDGER] schema=lower_missing_demand_v1 event=demand seq=0 iteration=0 context=initial reason=call_target owner_kind=top_level owner_id=0x0 requested_id=0x1 materialized_id=0x0 enqueue=1 function_count_before=1 function_count_after=1 pending_before=0 pending_after=0 hir_arg_shape_id=0x1 shape_mismatch_count=0 shape_ambiguous=0 outcome=deferred handoff=1 resolution_id=1\n'
} >"$BAD_HANDOFF_LOG"
expect_failure bad_handoff "$BAD_HANDOFF_LOG"

# Decimal fields are bounded before Bash arithmetic so hostile input cannot
# wrap counters or turn the analyzer into an unbounded arithmetic operation.
BAD_NUMERIC_LOG="$WORK_DIR/bad_numeric.log"
{
  checkpoint 0 initial 0
  checkpoint 0 initial 1
  printf '[LOWER_MISSING_LEDGER] schema=lower_missing_demand_v1 event=summary iteration=0 context=initial emitted=0 overflow=0 unfinished=999999999999999999999999999999 limit=4 function_count_start=1 function_count_end=1 pending_start=0 pending_end=0 complete=1\n'
} >"$BAD_NUMERIC_LOG"
expect_failure bad_numeric "$BAD_NUMERIC_LOG"

if LOWER_MISSING_ANALYZER_MAX_ROWS=999999999999999999999999 \
   bash "$ANALYZER" "$BAD_NUMERIC_LOG" >"$WORK_DIR/bad_cap.out" 2>&1; then
  echo "FAIL[bad_cap]: unbounded cap was accepted" >&2
  exit 1
fi
echo "PASS[bad_cap]: rejected as expected"

# Duplicate fields and locally valid but globally inconsistent summaries are
# rejected instead of being normalized by last-wins parsing.
DUPLICATE_LOG="$WORK_DIR/duplicate.log"
{
  checkpoint 0 initial 0
  printf '[LOWER_MISSING_LEDGER] schema=lower_missing_demand_v1 event=demand seq=0 iteration=0 context=initial context=final reason=call_target owner_kind=top_level owner_id=0x0 requested_id=0x1 materialized_id=0x0 enqueue=1 function_count_before=1 function_count_after=1 pending_before=0 pending_after=0 hir_arg_shape_id=0x1 shape_mismatch_count=0 shape_ambiguous=0 outcome=deferred handoff=0 resolution_id=0 callsite_arena_id=0 callsite_expr_id=-1 def_arena_id=0 def_expr_id=-1 receiver_type_id=0 arg_count=0 block_type_id=0\n'
} >"$DUPLICATE_LOG"
expect_failure duplicate "$DUPLICATE_LOG"

INCONSISTENT_LOG="$WORK_DIR/inconsistent.log"
{
  checkpoint 0 initial 0
  demand 0x1 0x1 0 0 deferred 0x0
  checkpoint 1 initial 1
  summary 1 initial 1 0
} >"$INCONSISTENT_LOG"
expect_failure inconsistent "$INCONSISTENT_LOG"

if LOWER_MISSING_ANALYZER_MAX_LOG_BYTES=1 \
   bash "$ANALYZER" "$BAD_NUMERIC_LOG" >"$WORK_DIR/byte_cap.out" 2>&1; then
  echo "FAIL[byte_cap]: oversized input snapshot was accepted" >&2
  exit 1
fi
echo "PASS[byte_cap]: rejected as expected"

# The row cap is configurable and must fail closed before unbounded parsing.
ROW_CAP_LOG="$WORK_DIR/row_cap.log"
{
  checkpoint 0 initial 0
  checkpoint 1 initial 1
  summary 1 initial 1
} >"$ROW_CAP_LOG"
if LOWER_MISSING_ANALYZER_MAX_ROWS=2 bash "$ANALYZER" "$ROW_CAP_LOG" >"$WORK_DIR/row_cap.out" 2>&1; then
  echo "FAIL[row_cap]: cap was not enforced" >&2
  exit 1
fi
echo "PASS[row_cap]: rejected as expected"

# Distinct-ID state is bounded independently from the row stream.
ID_OVERFLOW_LOG="$WORK_DIR/id_overflow.log"
{
  checkpoint 0 initial 0
  demand 0x1 0x1 0 0 deferred 0x0
  demand 0x2 0x1 0 0 deferred 0x0 1
  checkpoint 1 initial 1
  summary 1 initial 1
} >"$ID_OVERFLOW_LOG"
if ! id_overflow_output="$(LOWER_MISSING_ANALYZER_MAX_IDS=1 bash "$ANALYZER" "$ID_OVERFLOW_LOG")"; then
  echo "FAIL[id_overflow]: analyzer rejected a valid bounded-ID fixture" >&2
  exit 1
fi
if [[ "$id_overflow_output" != *"distinct_requested_ids=1"* ||
      "$id_overflow_output" != *"distinct_id_overflow=1"* ||
      "$id_overflow_output" != *"stream_complete=1"* ]]; then
  echo "FAIL[id_overflow]: missing overflow receipt token" >&2
  echo "$id_overflow_output" >&2
  exit 1
fi
echo "PASS[id_overflow]: $id_overflow_output"

echo "lower_missing_demand_ledger_analyzer_ok"
