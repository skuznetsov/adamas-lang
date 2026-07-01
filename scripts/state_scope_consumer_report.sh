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
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/state-scope-consumer.XXXXXX")"
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

echo "# StateScope Consumer Report"
echo "compiler: $COMPILER"
echo "source: $SRC"
echo "compiler_rc: $compiler_rc"
echo "samples_per_section: $SAMPLES"
echo "note: report is a migration gate; malformed or missing required consumers fail"

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

  function selected_params(selected_def,    p) {
    p = index(selected_def, ";params=")
    if (p == 0) {
      return ""
    }
    return substr(selected_def, p + 8)
  }

  function has_short_type_param_annotation(params) {
    return params ~ /(^|[|,:(])[_A-Z]($|[|,):])/
  }

  function has_regular_untyped_param(params,    n, parts, i, token) {
    n = split(params, parts, "|")
    for (i = 1; i <= n; i++) {
      token = parts[i]
      if (token ~ /:untyped$/ && token !~ /^[*&]/) {
        return 1
      }
    }
    return 0
  }

  function has_skipped_untyped_param(params,    n, parts, i, token) {
    n = split(params, parts, "|")
    for (i = 1; i <= n; i++) {
      token = parts[i]
      if (token ~ /:untyped$/ && token ~ /^[*&]/) {
        return 1
      }
    }
    return 0
  }

  function selected_param_class(params) {
    if (params == "") {
      return "params_unparsed"
    }
    if (params == "none") {
      return "no_regular_params"
    }
    if (has_regular_untyped_param(params)) {
      return "regular_untyped_params"
    }
    if (has_skipped_untyped_param(params)) {
      return "skipped_untyped_params"
    }
    if (has_short_type_param_annotation(params)) {
      return "short_type_params"
    }
    return "concrete_typed_params"
  }

  function target_map_class(target_map) {
    if (target_map == "") {
      return "target_map_empty"
    }
    return "target_map_present"
  }

  function call_arg_shape(call_arg_types,    n, parts) {
    if (call_arg_types == "" || call_arg_types == "nil") {
      return "call_args_none"
    }
    n = split(call_arg_types, parts, ",")
    if (n == 1) {
      return "call_args_1"
    }
    if (n <= 4) {
      return "call_args_2_4"
    }
    if (n <= 16) {
      return "call_args_5_16"
    }
    return "call_args_17_plus"
  }

  function blocked_class(consumer, decision, selected_def, result, migration, validation, call_arg_types,    params) {
    if (migration == "blocked_unknown") {
      return "blocked_unknown.needs_owner"
    }

    if (validation != "diagnostic_only") {
      return ""
    }

    params = selected_params(selected_def)
    if (params == "") {
      return "legacy_shim.params_unparsed"
    }
    if (params == "none") {
      return "legacy_shim.no_regular_params"
    }
    if (result == "1" && call_arg_types == "") {
      return "legacy_shim.untyped_missing_callsite_args"
    }
    if (has_regular_untyped_param(params)) {
      return "legacy_shim.regular_untyped_param_review"
    }
    if (has_skipped_untyped_param(params)) {
      return "legacy_shim.skipped_untyped_params"
    }
    if (has_short_type_param_annotation(params)) {
      return "legacy_shim.short_type_param_review"
    }

    return "legacy_shim.concrete_typed_params"
  }

  function owner_result_for(migration) {
    if (migration == "migrate_to_state_scope") {
      return "1"
    }
    if (migration == "migrate_to_materialization_registry" || migration == "rejected_ambient") {
      return "0"
    }
    if (migration == "keep_legacy_shim") {
      return "legacy"
    }
    return "unknown"
  }

  function owned_candidate_class(migration) {
    if (migration == "migrate_to_state_scope") {
      return "state_scope"
    }
    if (migration == "migrate_to_materialization_registry") {
      return "materialization_registry"
    }
    if (migration == "rejected_ambient") {
      return "ambient_rejected"
    }
    return ""
  }

  /^\[STATE_SCOPE_CONSUMER\]/ {
    rows++
    consumer = field("consumer")
    decision = field("decision")
    requested = field("requested")
    target = field("target")
    selected_def = field("selected_def")
    authority = field("authority")
    migration = field("migration")
    validation = field("validation")
    ambient = field("ambient_map")
    target_map = field("target_map")
    call_arg_types = field("call_arg_types")
    result = field("result")
    last_row = $0

    consumer_count[consumer]++
    decision_count[decision]++
    authority_count[authority]++
    migration_count[migration]++
    validation_count[validation]++

    if (consumer == "" || decision == "" || requested == "" || target == "" ||
        selected_def == "" || authority == "" || migration == "" ||
        validation == "" || result == "") {
      malformed++
      keep_sample("malformed", $0)
    }

    if (authority != "callsite" &&
        authority != "target_materialization" &&
        authority != "body_substitution" &&
        authority != "legacy_shim" &&
        authority != "rejected_ambient") {
      invalid_authority++
      keep_sample("invalid_authority", $0)
    }

    if (migration != "migrate_to_state_scope" &&
        migration != "migrate_to_materialization_registry" &&
        migration != "keep_legacy_shim" &&
        migration != "blocked_unknown" &&
        migration != "rejected_ambient") {
      invalid_migration++
      keep_sample("invalid_migration", $0)
    }

    if (validation != "owned" &&
        validation != "ambient_rejected" &&
        validation != "diagnostic_only") {
      invalid_validation++
      keep_sample("invalid_validation", $0)
    }

    if (validation == "ambient_rejected" && ambient == "") {
      rejected_without_ambient++
      keep_sample("rejected_without_ambient", $0)
    }

    if (validation == "diagnostic_only" || migration == "blocked_unknown") {
      blocked_rows++
      keep_sample("blocked_rows", $0)
      bclass = blocked_class(consumer, decision, selected_def, result, migration, validation, call_arg_types)
      if (bclass == "") {
        unclassified_blocked++
        keep_sample("unclassified_blocked", $0)
      } else {
        blocked_class_count[bclass]++
        keep_sample("blocked_class:" bclass, $0)
      }
    }

    if (authority == "target_materialization" && target_map == "") {
      target_without_map++
      keep_sample("target_without_map", $0)
    }

    if (authority == "callsite" && call_arg_types == "") {
      callsite_without_args++
      keep_sample("callsite_without_args", $0)
    }

    owner_result = owner_result_for(migration)
    candidate_class = owned_candidate_class(migration)
    if (candidate_class != "") {
      owned_candidate_rows++
      owned_candidate_count[candidate_class]++
      owner_key = candidate_class ".legacy_result_" result
      owner_result_count[owner_key]++
      keep_sample("owned_candidate:" candidate_class, $0)
      if (owner_result == "unknown" || owner_result == "legacy") {
        owner_result_unknown++
        keep_sample("owner_result_unknown", $0)
      } else if (owner_result != result) {
        owned_would_change++
        keep_sample("owned_would_change", $0)
      }
    }

    if (migration == "migrate_to_materialization_registry") {
      matreg_rows++
      mat_result = "legacy_result_" result
      matreg_result_count[mat_result]++
      matreg_consumer_result_count[consumer "." mat_result]++
      matreg_decision_result_count[decision "." mat_result]++
      matreg_consumer_decision_result_count[consumer "." decision "." mat_result]++

      params = selected_params(selected_def)
      param_class = selected_param_class(params)
      matreg_param_result_count[param_class "." mat_result]++

      tmap_class = target_map_class(target_map)
      matreg_target_map_result_count[tmap_class "." mat_result]++

      carg_shape = call_arg_shape(call_arg_types)
      matreg_call_arg_result_count[carg_shape "." mat_result]++

      keep_sample("materialization_registry:" mat_result, $0)
      keep_sample("materialization_registry:" consumer "." decision "." mat_result, $0)
    }
  }

  END {
    print ""
    print "## Counts"
    print "rows=" rows + 0
    print "malformed=" malformed + 0
    print "invalid_authority=" invalid_authority + 0
    print "invalid_migration=" invalid_migration + 0
    print "invalid_validation=" invalid_validation + 0
    print "rejected_without_ambient=" rejected_without_ambient + 0
    print "blocked_rows=" blocked_rows + 0
    print "unclassified_blocked=" unclassified_blocked + 0
    print "owned_candidate_rows=" owned_candidate_rows + 0
    print "owner_result_unknown=" owner_result_unknown + 0
    print "owned_would_change=" owned_would_change + 0
    print "target_without_map=" target_without_map + 0
    print "callsite_without_args=" callsite_without_args + 0

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
    print "## Authorities"
    for (a in authority_count) {
      print a "=" authority_count[a]
    }

    print ""
    print "## Migrations"
    for (m in migration_count) {
      print m "=" migration_count[m]
    }

    print ""
    print "## Validations"
    for (v in validation_count) {
      print v "=" validation_count[v]
    }

    print ""
    print "## Blocked Classification"
    known_blocked[1] = "blocked_unknown.needs_owner"
    known_blocked[2] = "legacy_shim.params_unparsed"
    known_blocked[3] = "legacy_shim.no_regular_params"
    known_blocked[4] = "legacy_shim.untyped_missing_callsite_args"
    known_blocked[5] = "legacy_shim.regular_untyped_param_review"
    known_blocked[6] = "legacy_shim.skipped_untyped_params"
    known_blocked[7] = "legacy_shim.short_type_param_review"
    known_blocked[8] = "legacy_shim.concrete_typed_params"
    for (i = 1; i <= 8; i++) {
      bc = known_blocked[i]
      print bc "=" blocked_class_count[bc] + 0
    }

    print ""
    print "## Owned Candidate Classification"
    known_owned[1] = "state_scope"
    known_owned[2] = "materialization_registry"
    known_owned[3] = "ambient_rejected"
    for (i = 1; i <= 3; i++) {
      oc = known_owned[i]
      print oc "=" owned_candidate_count[oc] + 0
    }

    print ""
    print "## Proposed Owner-Result Probe"
    known_parity[1] = "state_scope.legacy_result_1"
    known_parity[2] = "state_scope.legacy_result_0"
    known_parity[3] = "materialization_registry.legacy_result_1"
    known_parity[4] = "materialization_registry.legacy_result_0"
    known_parity[5] = "ambient_rejected.legacy_result_1"
    known_parity[6] = "ambient_rejected.legacy_result_0"
    for (i = 1; i <= 6; i++) {
      op = known_parity[i]
      print op "=" owner_result_count[op] + 0
    }

    print ""
    print "## MaterializationRegistry Attribution"
    print "materialization_registry_rows=" matreg_rows + 0

    print ""
    print "### MaterializationRegistry Result"
    known_mat_result[1] = "legacy_result_1"
    known_mat_result[2] = "legacy_result_0"
    for (i = 1; i <= 2; i++) {
      mr = known_mat_result[i]
      print mr "=" matreg_result_count[mr] + 0
    }

    print ""
    print "### MaterializationRegistry Consumer Result"
    for (k in matreg_consumer_result_count) {
      print k "=" matreg_consumer_result_count[k]
    }

    print ""
    print "### MaterializationRegistry Decision Result"
    for (k in matreg_decision_result_count) {
      print k "=" matreg_decision_result_count[k]
    }

    print ""
    print "### MaterializationRegistry Consumer Decision Result"
    for (k in matreg_consumer_decision_result_count) {
      print k "=" matreg_consumer_decision_result_count[k]
    }

    print ""
    print "### MaterializationRegistry Selected Param Class Result"
    known_param_class[1] = "params_unparsed"
    known_param_class[2] = "no_regular_params"
    known_param_class[3] = "regular_untyped_params"
    known_param_class[4] = "skipped_untyped_params"
    known_param_class[5] = "short_type_params"
    known_param_class[6] = "concrete_typed_params"
    for (i = 1; i <= 6; i++) {
      pc = known_param_class[i]
      for (j = 1; j <= 2; j++) {
        mr = known_mat_result[j]
        print pc "." mr "=" matreg_param_result_count[pc "." mr] + 0
      }
    }

    print ""
    print "### MaterializationRegistry Target Map Result"
    known_tmap[1] = "target_map_empty"
    known_tmap[2] = "target_map_present"
    for (i = 1; i <= 2; i++) {
      tm = known_tmap[i]
      for (j = 1; j <= 2; j++) {
        mr = known_mat_result[j]
        print tm "." mr "=" matreg_target_map_result_count[tm "." mr] + 0
      }
    }

    print ""
    print "### MaterializationRegistry Call Arg Shape Result"
    known_carg[1] = "call_args_none"
    known_carg[2] = "call_args_1"
    known_carg[3] = "call_args_2_4"
    known_carg[4] = "call_args_5_16"
    known_carg[5] = "call_args_17_plus"
    for (i = 1; i <= 5; i++) {
      ca = known_carg[i]
      for (j = 1; j <= 2; j++) {
        mr = known_mat_result[j]
        print ca "." mr "=" matreg_call_arg_result_count[ca "." mr] + 0
      }
    }

    for (i = 1; i <= 2; i++) {
      mr = known_mat_result[i]
      bucket = "materialization_registry:" mr
      if (sample_count[bucket] > 0) {
        print ""
        print "## Sample " bucket
        for (j = 1; j <= sample_count[bucket]; j++) {
          print sample[bucket, j]
        }
      }
    }

    for (i = 1; i <= 3; i++) {
      oc = known_owned[i]
      bucket = "owned_candidate:" oc
      if (sample_count[bucket] > 0) {
        print ""
        print "## Sample " bucket
        for (j = 1; j <= sample_count[bucket]; j++) {
          print sample[bucket, j]
        }
      }
    }

    for (i = 1; i <= 8; i++) {
      bc = known_blocked[i]
      bucket = "blocked_class:" bc
      if (sample_count[bucket] > 0) {
        print ""
        print "## Sample " bucket
        for (j = 1; j <= sample_count[bucket]; j++) {
          print sample[bucket, j]
        }
      }
    }

    print ""
    print "## Last Row"
    print last_row

    buckets[1] = "malformed"
    buckets[2] = "invalid_authority"
    buckets[3] = "invalid_migration"
    buckets[4] = "invalid_validation"
    buckets[5] = "rejected_without_ambient"
    buckets[6] = "blocked_rows"
    buckets[7] = "target_without_map"
    buckets[8] = "callsite_without_args"
    buckets[9] = "unclassified_blocked"
    buckets[10] = "owner_result_unknown"
    buckets[11] = "owned_would_change"
    for (i = 1; i <= 11; i++) {
      bucket = buckets[i]
      if (sample_count[bucket] > 0) {
        print ""
        print "## Sample " bucket
        for (j = 1; j <= sample_count[bucket]; j++) {
          print sample[bucket, j]
        }
      }
    }

    if (malformed || invalid_authority || invalid_migration ||
        invalid_validation || rejected_without_ambient || unclassified_blocked ||
        owner_result_unknown) {
      exit 7
    }
  }
' "$LOG"

required_consumers=(
  "prefer_callsite_specialization"
  "lower_function_if_needed.callsite_args"
  "lower_function_if_needed.suffix_types"
  "lower_function_if_needed.override"
  "lower_call.remangle"
  "def_has_untyped_regular_param"
  "raw_annotation_needs_callsite_specialization"
)

missing=0
echo ""
echo "## Required Consumers"
for consumer in "${required_consumers[@]}"; do
  if grep -q "^\[STATE_SCOPE_CONSUMER\].* consumer=${consumer} " "$LOG"; then
    echo "${consumer}=present"
  else
    echo "${consumer}=missing"
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  echo "FAIL: required StateScope consumer missing" >&2
  if [[ "$compiler_rc" -ne 0 ]]; then
    echo "" >&2
    echo "## Nonzero Compiler Tail" >&2
    tail -60 "$LOG" >&2 || true
  fi
  exit 8
fi

if [[ "$compiler_rc" -ne 0 ]]; then
  echo ""
  echo "## Nonzero Compiler Tail"
  tail -60 "$LOG" || true
fi
