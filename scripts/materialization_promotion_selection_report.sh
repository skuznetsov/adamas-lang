#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler> [source.cr [compiler-args...]]" >&2
  echo "env: TIMEOUT=180 MEM_MB=4096 SAMPLES=8 ALLOW_NO_ROWS=0 NO_ROW_REASON=<reason>" >&2
  echo "env: PREFERRED_CONSUMER=lower_function_if_needed.override GENERATED_STAGE_STATUS=not_checked" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
shift

TIMEOUT="${TIMEOUT:-180}"
MEM_MB="${MEM_MB:-4096}"
SAMPLES="${SAMPLES:-8}"
ALLOW_NO_ROWS="${ALLOW_NO_ROWS:-0}"
NO_ROW_REASON="${NO_ROW_REASON:-not_checked}"
PREFERRED_CONSUMER="${PREFERRED_CONSUMER:-lower_function_if_needed.override}"
GENERATED_STAGE_STATUS="${GENERATED_STAGE_STATUS:-not_checked}"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/materialization-promotion-selection.XXXXXX")"
LOG="$TMP_DIR/compile.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ $# -eq 0 ]]; then
  SRC="$TMP_DIR/repro.cr"
  OUT="$TMP_DIR/repro.bin"
  cat >"$SRC" <<'CR'
class Box(T)
  def initialize(@value : T)
  end

  def value
    @value
  end
end

class OwnerCache
  @owners = Hash(UInt64, NamedTuple(class_name: String?, method_name: String?, is_class: Bool)).new

  def write(id : UInt64, flag : Bool)
    class_name = flag ? "Box" : nil
    method_name = flag ? nil : "initialize"
    @owners[id] = {class_name: class_name, method_name: method_name, is_class: flag}
  end

  def read(id : UInt64)
    @owners[id]?
  end
end

box = Box(Int32).new(7)
cache = OwnerCache.new
cache.write(1_u64, true)
puts box.value
puts cache.read(1_u64).nil? ? 0 : 1
CR
  COMPILE_ARGS=("$SRC" -o "$OUT")
else
  SRC="$1"
  shift
  COMPILE_ARGS=("$SRC" "$@")
fi

set +e
ADAMAS_MATERIALIZATION_DECISION_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT" "$MEM_MB" \
  "${COMPILE_ARGS[@]}" >"$LOG" 2>&1
compiler_rc=$?
set -e

known_consumers=(
  "prefer_callsite_specialization"
  "lower_function_if_needed.callsite_args"
  "lower_function_if_needed.suffix_types"
  "lower_function_if_needed.override"
  "lower_call.remangle"
  "def_has_untyped_regular_param"
  "raw_annotation_needs_callsite_specialization"
)

if ! grep -q '^\[MAT_DECISION\]' "$LOG"; then
  if [[ "$ALLOW_NO_ROWS" == "1" ]]; then
    echo "# Materialization Promotion Selection Report"
    echo "compiler: $COMPILER"
    echo "source: $SRC"
    echo "compiler_rc: $compiler_rc"
    echo "samples_per_section: $SAMPLES"
    echo "preferred_consumer: $PREFERRED_CONSUMER"
    echo "generated_stage_status: $GENERATED_STAGE_STATUS"
    echo "no_row_reason: $NO_ROW_REASON"
    echo "note: no MaterializationDecision rows; reporting explicit seam residual"
    echo ""
    echo "## Counts"
    echo "rows=0"
    echo "malformed=0"
    echo "eligible_count=0"
    echo "selected_count=0"
    echo ""
    echo "## Candidate Selection"
    for consumer in "${known_consumers[@]}"; do
      echo "[PROMOTION_SELECTION] consumer=${consumer} row_count=0 selection_status=rejected_unreached generated_stage_status=${GENERATED_STAGE_STATUS} no_row_reason=${NO_ROW_REASON}"
    done
    exit 0
  fi

  echo "FAIL: no [MAT_DECISION] materialization decision rows emitted" >&2
  echo "compiler_rc=$compiler_rc" >&2
  tail -100 "$LOG" >&2 || true
  exit 1
fi

echo "# Materialization Promotion Selection Report"
echo "compiler: $COMPILER"
echo "source: $SRC"
echo "compiler_rc: $compiler_rc"
echo "samples_per_section: $SAMPLES"
echo "preferred_consumer: $PREFERRED_CONSUMER"
echo "generated_stage_status: $GENERATED_STAGE_STATUS"
echo "note: consumes existing MAT_DECISION rows; does not enable a new compiler ledger"

awk \
  -v samples="$SAMPLES" \
  -v preferred="$PREFERRED_CONSUMER" \
  -v generated_stage="$GENERATED_STAGE_STATUS" \
  -v known_consumers="$(IFS=,; echo "${known_consumers[*]}")" '
  function field(name,    i, p) {
    for (i = 1; i <= NF; i++) {
      p = index($i, "=")
      if (p > 0 && substr($i, 1, p - 1) == name) {
        return substr($i, p + 1)
      }
    }
    return ""
  }

  function keep_sample(bucket, row) {
    if (sample_count[bucket] < samples) {
      sample_count[bucket]++
      if (length(row) > 1200) {
        sample[bucket, sample_count[bucket]] = substr(row, 1, 1200) "...<truncated>"
      } else {
        sample[bucket, sample_count[bucket]] = row
      }
    }
  }

  function bump(map, key) {
    map[key]++
  }

  function append_known(consumer,    i) {
    if (!(consumer in consumer_seen)) {
      consumer_seen[consumer] = 1
      consumer_order[++consumer_order_count] = consumer
    }
  }

  function selection_status(consumer) {
    if (consumer_rows[consumer] == 0) {
      return "rejected_unreached"
    }
    if (consumer_missing[consumer] > 0 || consumer_invalid[consumer] > 0) {
      return "rejected_missing_owner_fields"
    }
    if (consumer_would_change[consumer] > 0) {
      return "rejected_broad_would_change"
    }
    if (consumer == preferred) {
      return "eligible_promote_owner"
    }
    if (consumer == "lower_call.remangle") {
      return "rejected_backend_only"
    }
    return "rejected_requires_new_oracle"
  }

  function print_counts_for(prefix, consumer, map,    key, printed) {
    printed = 0
    for (key in map) {
      split(key, parts, SUBSEP)
      if (parts[1] == consumer) {
        print prefix " consumer=" consumer " bucket=" parts[2] " count=" map[key]
        printed = 1
      }
    }
    if (!printed) {
      print prefix " consumer=" consumer " bucket=none count=0"
    }
  }

  BEGIN {
    known_count = split(known_consumers, known, ",")
    for (i = 1; i <= known_count; i++) {
      append_known(known[i])
    }
  }

  /^\[MAT_DECISION\]/ {
    rows++
    consumer = field("consumer")
    source_decision = field("source_decision")
    requested = field("requested")
    target = field("target")
    selected_def = field("selected_def")
    param_class = field("param_class")
    state_scope = field("state_scope")
    owner = field("owner")
    decision = field("decision")
    reason = field("reason")
    legacy_result = field("legacy_result")
    would_change = field("would_change")
    target_map = field("target_map")
    call_arg_types = field("call_arg_types")
    arg_abi = field("arg_abi")
    block_abi = field("block_abi")
    validation = field("validation")
    last_row = $0

    append_known(consumer)
    consumer_rows[consumer]++
    bump(decision_count, consumer SUBSEP decision)
    bump(reason_count, consumer SUBSEP reason)
    bump(param_class_count, consumer SUBSEP param_class)
    bump(state_scope_count, consumer SUBSEP state_scope)
    bump(arg_abi_count, consumer SUBSEP arg_abi)
    bump(block_abi_count, consumer SUBSEP block_abi)
    bump(legacy_result_count, consumer SUBSEP legacy_result)
    bump(would_change_count, consumer SUBSEP would_change)

    if (consumer == "" || source_decision == "" || requested == "" ||
        target == "" || selected_def == "" || param_class == "" ||
        state_scope == "" || owner == "" || decision == "" || reason == "" ||
        legacy_result == "" || would_change == "" || target_map == "" ||
        call_arg_types == "" || arg_abi == "" || block_abi == "" ||
        validation == "") {
      malformed++
      consumer_missing[consumer]++
      keep_sample("malformed", $0)
    }

    if (owner != "materialization_registry" &&
        owner != "semantic_state_scope" &&
        owner != "call_resolution" &&
        owner != "backend_mechanical" &&
        owner != "rejected") {
      invalid_owner++
      consumer_invalid[consumer]++
      keep_sample("invalid_owner", $0)
    }

    if (legacy_result != "0" && legacy_result != "1") {
      invalid_legacy_result++
      consumer_invalid[consumer]++
      keep_sample("invalid_legacy_result", $0)
    }

    if (would_change != "0" && would_change != "1" && would_change != "legacy") {
      invalid_would_change++
      consumer_invalid[consumer]++
      keep_sample("invalid_would_change", $0)
    }

    if (would_change == "1") {
      consumer_would_change[consumer]++
      keep_sample("would_change", $0)
    }
  }

  END {
    print ""
    print "## Counts"
    print "rows=" rows + 0
    print "malformed=" malformed + 0
    print "invalid_owner=" invalid_owner + 0
    print "invalid_legacy_result=" invalid_legacy_result + 0
    print "invalid_would_change=" invalid_would_change + 0

    print ""
    print "## Candidate Selection"
    for (i = 1; i <= consumer_order_count; i++) {
      consumer = consumer_order[i]
      status = selection_status(consumer)
      if (status == "eligible_promote_owner") {
        eligible_count++
        selected_count++
      }
      print "[PROMOTION_SELECTION] consumer=" consumer \
        " row_count=" consumer_rows[consumer] + 0 \
        " missing_owner_fields=" consumer_missing[consumer] + 0 \
        " invalid_owner_fields=" consumer_invalid[consumer] + 0 \
        " would_change_rows=" consumer_would_change[consumer] + 0 \
        " selection_status=" status \
        " generated_stage_status=" generated_stage
    }

    print ""
    print "## Selection Counts"
    print "eligible_count=" eligible_count + 0
    print "selected_count=" selected_count + 0

    print ""
    print "## Consumer Decision Buckets"
    for (i = 1; i <= consumer_order_count; i++) {
      print_counts_for("[PROMOTION_BUCKET] kind=decision", consumer_order[i], decision_count)
    }

    print ""
    print "## Consumer Reason Buckets"
    for (i = 1; i <= consumer_order_count; i++) {
      print_counts_for("[PROMOTION_BUCKET] kind=reason", consumer_order[i], reason_count)
    }

    print ""
    print "## Consumer Param Class Buckets"
    for (i = 1; i <= consumer_order_count; i++) {
      print_counts_for("[PROMOTION_BUCKET] kind=param_class", consumer_order[i], param_class_count)
    }

    print ""
    print "## Consumer State Scope Buckets"
    for (i = 1; i <= consumer_order_count; i++) {
      print_counts_for("[PROMOTION_BUCKET] kind=state_scope", consumer_order[i], state_scope_count)
    }

    print ""
    print "## Consumer ABI Buckets"
    for (i = 1; i <= consumer_order_count; i++) {
      print_counts_for("[PROMOTION_BUCKET] kind=arg_abi", consumer_order[i], arg_abi_count)
      print_counts_for("[PROMOTION_BUCKET] kind=block_abi", consumer_order[i], block_abi_count)
    }

    print ""
    print "## Consumer Legacy/Would-Change Buckets"
    for (i = 1; i <= consumer_order_count; i++) {
      print_counts_for("[PROMOTION_BUCKET] kind=legacy_result", consumer_order[i], legacy_result_count)
      print_counts_for("[PROMOTION_BUCKET] kind=would_change", consumer_order[i], would_change_count)
    }

    buckets[1] = "malformed"
    buckets[2] = "invalid_owner"
    buckets[3] = "invalid_legacy_result"
    buckets[4] = "invalid_would_change"
    buckets[5] = "would_change"
    for (i = 1; i <= 5; i++) {
      bucket = buckets[i]
      if (sample_count[bucket] > 0) {
        print ""
        print "## Sample " bucket
        for (s = 1; s <= sample_count[bucket]; s++) {
          print sample[bucket, s]
        }
      }
    }

    print ""
    print "## Last Row"
    if (last_row == "") {
      print "(none)"
    } else {
      print last_row
    }

    if (rows == 0 || malformed > 0 || invalid_owner > 0 ||
        invalid_legacy_result > 0 || invalid_would_change > 0 ||
        selected_count != 1) {
      exit 1
    }
  }
' "$LOG"
