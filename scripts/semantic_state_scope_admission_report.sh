#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler> [source.cr [compiler-args...]]" >&2
  echo "env: TIMEOUT=180 MEM_MB=4096 SAMPLES=8" >&2
  echo "env: PREFERRED_CONSUMER=prefer_callsite_specialization REQUIRE_PROMOTED=0" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
shift

TIMEOUT="${TIMEOUT:-180}"
MEM_MB="${MEM_MB:-4096}"
SAMPLES="${SAMPLES:-8}"
PREFERRED_CONSUMER="${PREFERRED_CONSUMER:-prefer_callsite_specialization}"
REQUIRE_PROMOTED="${REQUIRE_PROMOTED:-0}"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/semantic-state-scope-admission.XXXXXX")"
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

source_shape_for_prefer_callsite_specialization() {
  local source_file="$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"
  local helper_name="semantic_state_scope_prefer_callsite_specialization_shadow_untyped_regular_param?"
  local legacy_name="state_scope_consumer_def_has_untyped_regular_param?"

  awk -v helper="$helper_name" -v legacy="$legacy_name" '
    /private def prefer_callsite_specialization\(/ {
      in_method = 1
      next
    }
    in_method && /private def / {
      in_method = 0
    }
    in_method {
      if (index($0, helper) > 0) {
        helper_call = 1
      }
      if (index($0, legacy) > 0) {
        legacy_call = 1
      }
    }
    END {
      if (helper_call && !legacy_call) {
        print "already_promoted_shadow"
      } else if (legacy_call) {
        print "legacy_direct_edge"
      } else {
        print "missing_old_edge"
      }
    }
  ' "$source_file"
}

set +e
ADAMAS_STATE_SCOPE_CONSUMER_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT" "$MEM_MB" \
  "${COMPILE_ARGS[@]}" >"$LOG" 2>&1
compiler_rc=$?
set -e

if ! grep -q '^\[STATE_SCOPE_CONSUMER\]' "$LOG"; then
  echo "FAIL: no [STATE_SCOPE_CONSUMER] consumer rows emitted" >&2
  echo "compiler_rc=$compiler_rc" >&2
  tail -100 "$LOG" >&2 || true
  exit 1
fi

PREFERRED_SOURCE_SHAPE="not_checked"
if [[ "$PREFERRED_CONSUMER" == "prefer_callsite_specialization" ]]; then
  PREFERRED_SOURCE_SHAPE="$(source_shape_for_prefer_callsite_specialization)"
fi

echo "# SemanticStateScope Admission Report"
echo "compiler: $COMPILER"
echo "source: $SRC"
echo "compiler_rc: $compiler_rc"
echo "samples_per_section: $SAMPLES"
echo "preferred_consumer: $PREFERRED_CONSUMER"
echo "preferred_source_shape: $PREFERRED_SOURCE_SHAPE"
echo "require_promoted: $REQUIRE_PROMOTED"
echo "note: selects one StateScope owner-consumption seam; it does not change compiler behavior"

awk \
  -v samples="$SAMPLES" \
  -v preferred="$PREFERRED_CONSUMER" \
  -v preferred_source_shape="$PREFERRED_SOURCE_SHAPE" \
  -v require_promoted="$REQUIRE_PROMOTED" '
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

  function append_known(consumer) {
    if (!(consumer in consumer_seen)) {
      consumer_seen[consumer] = 1
      consumer_order[++consumer_order_count] = consumer
    }
  }

  function bump(map, key) {
    map[key]++
  }

  function selection_status(consumer) {
    if (consumer_rows[consumer] == 0) {
      return "rejected_unreached"
    }
    if (consumer == "lower_function_if_needed.override") {
      return "rejected_materialization_override_promoted"
    }
    if (consumer == "def_has_untyped_regular_param" ||
        consumer == "raw_annotation_needs_callsite_specialization") {
      return "rejected_predicate_helper_not_consumer"
    }
    if (consumer == "lower_call.remangle") {
      return "rejected_backend_adjacent"
    }
    if (consumer == "lower_function_if_needed.callsite_args" ||
        consumer == "lower_function_if_needed.suffix_types") {
      return "rejected_later_keep_requested_name_seam"
    }
    if (consumer == preferred) {
      if (preferred_source_shape == "already_promoted_shadow") {
        return "already_promoted_shadow"
      }
      if (preferred_source_shape == "legacy_direct_edge") {
        return "eligible_scope_owner"
      }
      return "rejected_missing_source_edge"
    }
    return "rejected_requires_new_oracle"
  }

  BEGIN {
    append_known("prefer_callsite_specialization")
    append_known("lower_function_if_needed.callsite_args")
    append_known("lower_function_if_needed.suffix_types")
    append_known("lower_function_if_needed.override")
    append_known("lower_call.remangle")
    append_known("def_has_untyped_regular_param")
    append_known("raw_annotation_needs_callsite_specialization")
  }

  /^\[STATE_SCOPE_CONSUMER\]/ {
    rows++
    consumer = field("consumer")
    decision = field("decision")
    requested = field("requested")
    target = field("target")
    selected_def = field("selected_def")
    result = field("result")
    authority = field("authority")
    migration = field("migration")
    validation = field("validation")
    ambient_map = field("ambient_map")
    target_map = field("target_map")
    call_arg_types = field("call_arg_types")
    last_row = $0

    append_known(consumer)
    consumer_rows[consumer]++
    bump(migration_count, consumer SUBSEP migration)
    bump(authority_count, consumer SUBSEP authority)
    bump(validation_count, consumer SUBSEP validation)
    bump(result_count, consumer SUBSEP result)
    bump(decision_count, consumer SUBSEP decision)

    if (consumer == "" || decision == "" || requested == "" || target == "" ||
        selected_def == "" || result == "" || authority == "" ||
        migration == "" || validation == "") {
      malformed++
      consumer_malformed[consumer]++
      keep_sample("malformed", $0)
    }

    if (consumer == preferred) {
      keep_sample("preferred", $0)
      if (migration == "migrate_to_state_scope") {
        preferred_state_scope_rows++
      } else if (migration == "migrate_to_materialization_registry") {
        preferred_materialization_rows++
      } else if (migration == "rejected_ambient") {
        preferred_rejected_ambient_rows++
      } else if (migration == "keep_legacy_shim") {
        preferred_legacy_shim_rows++
      } else {
        preferred_other_migration_rows++
      }
      if (validation == "diagnostic_only" ||
          migration == "blocked_unknown" ||
          migration == "keep_legacy_shim") {
        preferred_blocked_rows++
        keep_sample("preferred_blocked", $0)
      }
    }
  }

  END {
    print ""
    print "## Counts"
    print "rows=" rows + 0
    print "malformed=" malformed + 0
    print "preferred_rows=" consumer_rows[preferred] + 0
    print "preferred_state_scope_rows=" preferred_state_scope_rows + 0
    print "preferred_materialization_rows=" preferred_materialization_rows + 0
    print "preferred_rejected_ambient_rows=" preferred_rejected_ambient_rows + 0
    print "preferred_legacy_shim_rows=" preferred_legacy_shim_rows + 0
    print "preferred_blocked_rows=" preferred_blocked_rows + 0

    print ""
    print "## Candidate Selection"
    for (i = 1; i <= consumer_order_count; i++) {
      consumer = consumer_order[i]
      status = selection_status(consumer)
      if (status == "eligible_scope_owner") {
        eligible_count++
        selected_count++
      }
      if (status == "already_promoted_shadow") {
        already_promoted_count++
      }
      print "[STATE_SCOPE_ADMISSION] consumer=" consumer \
        " row_count=" consumer_rows[consumer] + 0 \
        " malformed=" consumer_malformed[consumer] + 0 \
        " source_shape=" (consumer == preferred ? preferred_source_shape : "not_checked") \
        " selection_status=" status
    }

    print ""
    print "eligible_count=" eligible_count + 0
    print "selected_count=" selected_count + 0
    print "already_promoted_count=" already_promoted_count + 0

    print ""
    print "## Preferred Migration Buckets"
    print "migrate_to_state_scope=" preferred_state_scope_rows + 0
    print "migrate_to_materialization_registry=" preferred_materialization_rows + 0
    print "rejected_ambient=" preferred_rejected_ambient_rows + 0
    print "keep_legacy_shim=" preferred_legacy_shim_rows + 0
    print "other_migration=" preferred_other_migration_rows + 0

    print ""
    print "## Preferred Samples"
    for (j = 1; j <= sample_count["preferred"]; j++) {
      print sample["preferred", j]
    }

    if (sample_count["preferred_blocked"] > 0) {
      print ""
      print "## Preferred Blocked Samples"
      for (j = 1; j <= sample_count["preferred_blocked"]; j++) {
        print sample["preferred_blocked", j]
      }
    }

    print ""
    print "## Last Row"
    print last_row

    if (malformed > 0) {
      exit 7
    }
    if (require_promoted == "1") {
      if (already_promoted_count != 1 || preferred_source_shape != "already_promoted_shadow") {
        exit 9
      }
    } else {
      if (selected_count != 1) {
        exit 8
      }
    }
  }
' "$LOG"
