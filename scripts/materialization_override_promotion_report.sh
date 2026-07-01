#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler> [source.cr [compiler-args...]]" >&2
  echo "env: TIMEOUT=180 MEM_MB=4096 SAMPLES=8 ALLOW_NO_ROWS=0 NO_ROW_REASON=<reason> CHECK_SOURCE_SHAPE=1" >&2
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
CHECK_SOURCE_SHAPE="${CHECK_SOURCE_SHAPE:-1}"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/materialization-override-promotion.XXXXXX")"
LOG="$TMP_DIR/compile.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

check_source_shape() {
  local source_file="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"
  local helper_name="materialization_override_shadow_untyped_regular_param?"

  if ! grep -q "def ${helper_name}" "$source_file"; then
    echo "FAIL: missing ${helper_name} helper" >&2
    return 1
  fi

  if ! awk -v helper="$helper_name" '
    /has_untyped_regular_param =/ {
      seen = 1
      window = 0
    }
    seen {
      window++
      if (index($0, helper) > 0) {
        found = 1
      }
      if (window > 8) {
        seen = 0
      }
    }
    END {
      exit(found ? 0 : 1)
    }
  ' "$source_file"; then
    echo "FAIL: override seam does not assign has_untyped_regular_param through ${helper_name}" >&2
    return 1
  fi

  if awk '
    /has_untyped_regular_param =/ {
      seen = 1
      window = 0
    }
    seen {
      window++
      if (index($0, "state_scope_consumer_def_has_untyped_regular_param?") > 0) {
        bad = 1
      }
      if (window > 8) {
        seen = 0
      }
    }
    END {
      exit(bad ? 0 : 1)
    }
  ' "$source_file"; then
    echo "FAIL: override seam still calls state_scope_consumer_def_has_untyped_regular_param? directly" >&2
    return 1
  fi
}

if [[ "$CHECK_SOURCE_SHAPE" == "1" ]]; then
  check_source_shape
fi

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
ADAMAS_MATERIALIZATION_OVERRIDE_PROMOTION_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT" "$MEM_MB" \
  "${COMPILE_ARGS[@]}" >"$LOG" 2>&1
compiler_rc=$?
set -e

if ! grep -q '^\[MAT_PROMOTION\]' "$LOG"; then
  if [[ "$ALLOW_NO_ROWS" == "1" ]]; then
    echo "# Materialization Override Promotion Report"
    echo "compiler: $COMPILER"
    echo "source: $SRC"
    echo "compiler_rc: $compiler_rc"
    echo "samples_per_section: $SAMPLES"
    echo "generated_stage_status: not_reached_named_residual"
    echo "no_row_reason: $NO_ROW_REASON"
    echo "note: no promoted override rows; reporting explicit seam residual"
    echo ""
    echo "## Counts"
    echo "rows=0"
    echo "malformed=0"
    echo "invalid_consumer=0"
    echo "invalid_source_decision=0"
    echo "invalid_promotion=0"
    echo "invalid_legacy_result=0"
    echo "invalid_owner_result=0"
    echo "invalid_emitted_result=0"
    echo "emitted_mismatch=0"
    exit 0
  fi

  echo "FAIL: no [MAT_PROMOTION] override promotion rows emitted" >&2
  echo "compiler_rc=$compiler_rc" >&2
  tail -100 "$LOG" >&2 || true
  exit 1
fi

echo "# Materialization Override Promotion Report"
echo "compiler: $COMPILER"
echo "source: $SRC"
echo "compiler_rc: $compiler_rc"
echo "samples_per_section: $SAMPLES"
echo "note: verifies override promotion consumes owned MaterializationDecision record in shadow/parity mode"

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

  /^\[MAT_PROMOTION\]/ {
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
    owner_result = field("owner_result")
    emitted_result = field("emitted_result")
    would_change = field("would_change")
    promotion = field("promotion")
    target_map = field("target_map")
    call_arg_types = field("call_arg_types")
    arg_abi = field("arg_abi")
    block_abi = field("block_abi")
    validation = field("validation")

    consumer_count[consumer]++
    decision_count[decision]++
    reason_count[reason]++
    owner_result_count[owner_result]++
    promotion_count[promotion]++

    if (consumer == "" || source_decision == "" || requested == "" ||
        target == "" || selected_def == "" || param_class == "" ||
        state_scope == "" || owner == "" || decision == "" || reason == "" ||
        legacy_result == "" || owner_result == "" || emitted_result == "" ||
        would_change == "" || promotion == "" || target_map == "" ||
        call_arg_types == "" || arg_abi == "" || block_abi == "" ||
        validation == "") {
      malformed++
      keep_sample("malformed", $0)
    }

    if (consumer != "lower_function_if_needed.override") {
      invalid_consumer++
      keep_sample("invalid_consumer", $0)
    }

    if (source_decision != "materialization_override") {
      invalid_source_decision++
      keep_sample("invalid_source_decision", $0)
    }

    if (promotion != "shadow_parity") {
      invalid_promotion++
      keep_sample("invalid_promotion", $0)
    }

    if (legacy_result != "0" && legacy_result != "1") {
      invalid_legacy_result++
      keep_sample("invalid_legacy_result", $0)
    }

    if (owner_result != "0" && owner_result != "1" && owner_result != "legacy") {
      invalid_owner_result++
      keep_sample("invalid_owner_result", $0)
    }

    if (emitted_result != "0" && emitted_result != "1") {
      invalid_emitted_result++
      keep_sample("invalid_emitted_result", $0)
    }

    if (legacy_result != emitted_result) {
      emitted_mismatch++
      keep_sample("emitted_mismatch", $0)
    }
  }

  END {
    print ""
    print "## Counts"
    print "rows=" rows + 0
    print "malformed=" malformed + 0
    print "invalid_consumer=" invalid_consumer + 0
    print "invalid_source_decision=" invalid_source_decision + 0
    print "invalid_promotion=" invalid_promotion + 0
    print "invalid_legacy_result=" invalid_legacy_result + 0
    print "invalid_owner_result=" invalid_owner_result + 0
    print "invalid_emitted_result=" invalid_emitted_result + 0
    print "emitted_mismatch=" emitted_mismatch + 0

    print ""
    print "## Consumers"
    for (c in consumer_count) {
      print c "=" consumer_count[c]
    }

    print ""
    print "## Decisions"
    for (d in decision_count) {
      print d "=" decision_count[d]
    }

    print ""
    print "## Owner Results"
    for (o in owner_result_count) {
      print o "=" owner_result_count[o]
    }

    print ""
    print "## Promotions"
    for (p in promotion_count) {
      print p "=" promotion_count[p]
    }

    print ""
    print "## Samples"
    for (bucket in sample_count) {
      print "### " bucket
      for (i = 1; i <= sample_count[bucket]; i++) {
        print sample[bucket, i]
      }
    }
  }
' "$LOG"
