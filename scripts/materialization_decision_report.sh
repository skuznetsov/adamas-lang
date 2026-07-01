#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler> [source.cr [compiler-args...]]" >&2
  echo "env: TIMEOUT=180 MEM_MB=4096 SAMPLES=8" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
shift

TIMEOUT="${TIMEOUT:-180}"
MEM_MB="${MEM_MB:-4096}"
SAMPLES="${SAMPLES:-8}"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/materialization-decision.XXXXXX")"
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

if ! grep -q '^\[MAT_DECISION\]' "$LOG"; then
  echo "FAIL: no [MAT_DECISION] materialization decision rows emitted" >&2
  echo "compiler_rc=$compiler_rc" >&2
  tail -100 "$LOG" >&2 || true
  exit 1
fi

echo "# Materialization Decision Report"
echo "compiler: $COMPILER"
echo "source: $SRC"
echo "compiler_rc: $compiler_rc"
echo "samples_per_section: $SAMPLES"
echo "note: report is a behavior-neutral MaterializationRegistry contract gate"

awk -v samples="$SAMPLES" '
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

  function valid_decision(value) {
    return value == "exact" ||
           value == "callsite_specialized" ||
           value == "target_materialized" ||
           value == "wrapper_required" ||
           value == "legacy_shim" ||
           value == "rejected_mismatch"
  }

  function valid_owner(value) {
    return value == "materialization_registry" ||
           value == "semantic_state_scope" ||
           value == "call_resolution" ||
           value == "backend_mechanical" ||
           value == "rejected"
  }

  function valid_reason(value) {
    return value == "regular_untyped_param_requires_callsite_symbol" ||
           value == "concrete_typed_param_uses_target_symbol" ||
           value == "short_type_param_requires_scope_disambiguation" ||
           value == "skipped_untyped_param_requires_legacy_shim" ||
           value == "no_regular_param_requires_target_symbol" ||
           value == "abi_shape_requires_wrapper" ||
           value == "exact_symbol_match" ||
           value == "insufficient_owner_evidence"
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

    consumer_count[consumer]++
    source_decision_count[source_decision]++
    decision_count[decision]++
    owner_count[owner]++
    reason_count[reason]++
    param_class_count[param_class]++
    state_scope_count[state_scope]++
    validation_count[validation]++
    would_change_count[would_change]++
    decision_param_count[decision "." param_class]++
    decision_legacy_count[decision ".legacy_result_" legacy_result]++

    if (consumer == "" || source_decision == "" || requested == "" ||
        target == "" || selected_def == "" || param_class == "" ||
        state_scope == "" || owner == "" || decision == "" || reason == "" ||
        legacy_result == "" || would_change == "" || target_map == "" ||
        call_arg_types == "" || arg_abi == "" || block_abi == "" ||
        validation == "") {
      malformed++
      keep_sample("malformed", $0)
    }

    if (!valid_decision(decision)) {
      invalid_decision++
      keep_sample("invalid_decision", $0)
    }

    if (!valid_owner(owner)) {
      invalid_owner++
      keep_sample("invalid_owner", $0)
    }

    if (!valid_reason(reason)) {
      invalid_reason++
      keep_sample("invalid_reason", $0)
    }

    if (legacy_result != "0" && legacy_result != "1") {
      invalid_legacy_result++
      keep_sample("invalid_legacy_result", $0)
    }

    if (would_change != "0" && would_change != "1" && would_change != "legacy") {
      invalid_would_change++
      keep_sample("invalid_would_change", $0)
    }

    if (decision == "legacy_shim") {
      legacy_shim_rows++
      keep_sample("legacy_shim", $0)
    }

    if (decision == "rejected_mismatch") {
      rejected_rows++
      keep_sample("rejected_mismatch", $0)
    }

    if (would_change == "1") {
      would_change_rows++
      keep_sample("would_change", $0)
    }
  }

  END {
    print ""
    print "## Counts"
    print "rows=" rows + 0
    print "malformed=" malformed + 0
    print "invalid_decision=" invalid_decision + 0
    print "invalid_owner=" invalid_owner + 0
    print "invalid_reason=" invalid_reason + 0
    print "invalid_legacy_result=" invalid_legacy_result + 0
    print "invalid_would_change=" invalid_would_change + 0
    print "would_change_rows=" would_change_rows + 0
    print "legacy_shim_rows=" legacy_shim_rows + 0
    print "rejected_rows=" rejected_rows + 0

    print ""
    print "## Decisions"
    for (d in decision_count) {
      print d "=" decision_count[d]
    }

    print ""
    print "## Owners"
    for (o in owner_count) {
      print o "=" owner_count[o]
    }

    print ""
    print "## Reasons"
    for (r in reason_count) {
      print r "=" reason_count[r]
    }

    print ""
    print "## Parameter Classes"
    for (p in param_class_count) {
      print p "=" param_class_count[p]
    }

    print ""
    print "## State Scopes"
    for (s in state_scope_count) {
      print s "=" state_scope_count[s]
    }

    print ""
    print "## Validations"
    for (v in validation_count) {
      print v "=" validation_count[v]
    }

    print ""
    print "## Would Change"
    for (w in would_change_count) {
      print w "=" would_change_count[w]
    }

    print ""
    print "## Consumers"
    for (c in consumer_count) {
      print c "=" consumer_count[c]
    }

    print ""
    print "## Source Decisions"
    for (sd in source_decision_count) {
      print sd "=" source_decision_count[sd]
    }

    print ""
    print "## Decision By Parameter Class"
    for (dp in decision_param_count) {
      print dp "=" decision_param_count[dp]
    }

    print ""
    print "## Decision By Legacy Result"
    for (dl in decision_legacy_count) {
      print dl "=" decision_legacy_count[dl]
    }

    buckets[1] = "malformed"
    buckets[2] = "invalid_decision"
    buckets[3] = "invalid_owner"
    buckets[4] = "invalid_reason"
    buckets[5] = "invalid_legacy_result"
    buckets[6] = "invalid_would_change"
    buckets[7] = "would_change"
    buckets[8] = "legacy_shim"
    buckets[9] = "rejected_mismatch"
    for (i = 1; i <= 9; i++) {
      bucket = buckets[i]
      if (sample_count[bucket] > 0) {
        print ""
        print "## Sample " bucket
        for (s = 1; s <= sample_count[bucket]; s++) {
          print sample[bucket, s]
        }
      }
    }

    if (rows == 0 ||
        malformed > 0 ||
        invalid_decision > 0 ||
        invalid_owner > 0 ||
        invalid_reason > 0 ||
        invalid_legacy_result > 0 ||
        invalid_would_change > 0) {
      exit 1
    }
  }
' "$LOG"
