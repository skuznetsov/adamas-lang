#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_workers1_mir_subphase_classifier.sh [source.cr]

Build/use a fresh generated s2 compiler and classify where the selected
workers=1 HIR-to-MIR OS-RSS resource lane first becomes high.

This is the post-0k-DT workers=1 MIR subphase selector. It uses explicit
debug-only MIR stop gates and /usr/bin/time -l OS RSS evidence. It does not use
GC non_gc accounting and does not admit behavior changes to MIR lowering,
optimization, worker policy, memory budgets, backend emission, NamedTuple/Tuple,
ambient maps, or BlockOwner.

Environment:
  KEEP_TMP=1                 Keep temp dirs for manual inspection.
  REQUIRE_CLASSIFICATION=1   Exit nonzero unless a terminal classification is
                             produced.
  REQUIRE_SUBPHASE=1         Exit nonzero unless a workers=1 MIR subphase is
                             selected or the gate is clean.
  HIGH_RSS_MB                Peak RSS threshold for "high" (default: 3072).
  STAGE1_COMPILER            Pass-through to generated_stage_llvm_entry_classifier.
  GENERATED_S2               Pass-through to generated_stage_llvm_entry_classifier.
  STAGE1_MODE                Pass-through stage1 mode (default inherited).
  STAGE2_BUILD_TIMEOUT       Pass-through generated s2 build timeout.
  STAGE2_BUILD_MEM_MB        Pass-through generated s2 build RSS cap.
  SMOKE_TIMEOUT              Stop-gate compile timeout (default: 120).
  SMOKE_MEM_MB               Stop-gate compile RSS cap (default: 4096).
  TAIL_LINES                 Nested classifier tail lines (default: 40).

Classifications:
  workers1_hir_resource_boundary
  workers1_mir_type_registration_resource_boundary
  workers1_mir_prepare_resource_boundary
  select_workers1_mir_body_lowering_resource_lane
  select_workers1_mir_optimization_resource_lane
  workers1_mir_after_optimization_resource_boundary
  workers1_mir_subphase_clean
  workers1_mir_subphase_classifier_missing_time_l
  workers1_mir_subphase_classifier_build_failed
  workers1_mir_subphase_stage1_control_high
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x /usr/bin/time ]]; then
  echo "classification=workers1_mir_subphase_classifier_missing_time_l"
  echo "reason=/usr/bin/time_missing"
  exit 9
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-workers1-mir-subphase.XXXXXX")"
NESTED_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
    [[ -n "$NESTED_TMP" ]] && echo "kept_classifier_tmp=$NESTED_TMP"
  else
    if [[ -n "$NESTED_TMP" && "$NESTED_TMP" == "$ROOT_DIR/tmp/generated-stage-llvm-entry."* ]]; then
      rm -rf "$NESTED_TMP"
    fi
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SOURCE="${1:-$TMP_DIR/full_prelude_puts42.cr}"
if [[ $# -eq 0 ]]; then
  cat >"$SOURCE" <<'CR'
puts 42
CR
fi

HIGH_RSS_MB="${HIGH_RSS_MB:-3072}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-120}"
SMOKE_MEM_MB="${SMOKE_MEM_MB:-4096}"
TAIL_LINES="${TAIL_LINES:-40}"
CLASSIFIER_OUT="$TMP_DIR/generated_stage_llvm_entry.out"

echo "# Generated Stage Workers1 MIR Subphase Classifier"
echo "repo=$ROOT_DIR"
echo "source=$SOURCE"
echo "high_rss_mb=$HIGH_RSS_MB"
echo "smoke_timeout=$SMOKE_TIMEOUT"
echo "smoke_mem_mb=$SMOKE_MEM_MB"
echo "require_classification=${REQUIRE_CLASSIFICATION:-0}"
echo "require_subphase=${REQUIRE_SUBPHASE:-0}"

set +e
KEEP_TMP=1 \
STAGE1_COMPILER="${STAGE1_COMPILER:-}" \
GENERATED_S2="${GENERATED_S2:-}" \
STAGE1_MODE="${STAGE1_MODE:-debug}" \
STAGE2_BUILD_TIMEOUT="${STAGE2_BUILD_TIMEOUT:-300}" \
STAGE2_BUILD_MEM_MB="${STAGE2_BUILD_MEM_MB:-4096}" \
SMOKE_TIMEOUT="$SMOKE_TIMEOUT" \
SMOKE_MEM_MB="$SMOKE_MEM_MB" \
TAIL_LINES="$TAIL_LINES" \
  "$ROOT_DIR/scripts/generated_stage_llvm_entry_classifier.sh" "$SOURCE" >"$CLASSIFIER_OUT" 2>&1
entry_rc=$?
set -e

value_of_file() {
  local key="$1"
  local file="$2"
  awk -F= -v k="$key" '
    $1 == k {
      print substr($0, index($0, "=") + 1)
      found = 1
      exit
    }
    END {
      if (!found) exit 1
    }
  ' "$file" 2>/dev/null || true
}

NESTED_TMP="$(value_of_file kept_tmp "$CLASSIFIER_OUT")"
STAGE1_PATH="$(value_of_file stage1 "$CLASSIFIER_OUT")"
S2_PATH="$(value_of_file generated_s2 "$CLASSIFIER_OUT")"

if [[ "$entry_rc" -ne 0 || ! -x "$S2_PATH" ]]; then
  echo "entry_classifier_rc=$entry_rc"
  echo "nested.classification=$(value_of_file classification "$CLASSIFIER_OUT")"
  echo "classification=workers1_mir_subphase_classifier_build_failed"
  echo "entry_classifier_tail:"
  tail -120 "$CLASSIFIER_OUT" || true
  exit 9
fi

parse_time_l_peak_rss_bytes() {
  local log="$1"
  awk '
    /maximum resident set size/ {
      print $1
      found = 1
    }
    END {
      if (!found) exit 1
    }
  ' "$log" 2>/dev/null | tail -1 || true
}

run_safe_exit_code() {
  local log="$1"
  awk '/^\[EXIT: / {
    gsub("\\[EXIT: ", "", $2)
    gsub("\\]", "", $2)
    print $2
  }' "$log" 2>/dev/null | tail -1 || true
}

run_safe_memory_kill_kb() {
  local log="$1"
  sed -nE 's/.*\[KILL\] Memory limit: ([0-9]+)KB.*/\1/p' "$log" | tail -1
}

run_stop_probe() {
  local label="$1"
  local compiler="$2"
  local stop_env="$3"
  local out_bin="$TMP_DIR/${label}.out"
  local log="$TMP_DIR/${label}.log"

  set +e
  env "$stop_env=1" ADAMAS_LLVM_WORKERS=1 \
    /usr/bin/time -l "$ROOT_DIR/scripts/run_safe.sh" "$compiler" "$SMOKE_TIMEOUT" "$SMOKE_MEM_MB" \
      "$SOURCE" -o "$out_bin" >"$log" 2>&1
  local rc=$?
  set -e

  local peak_bytes
  peak_bytes="$(parse_time_l_peak_rss_bytes "$log")"
  local peak_mb=0
  if [[ -n "$peak_bytes" ]]; then
    peak_mb=$(( (peak_bytes + 1048575) / 1048576 ))
  fi

  local exit_code
  exit_code="$(run_safe_exit_code "$log")"
  local kill_kb
  kill_kb="$(run_safe_memory_kill_kb "$log")"
  local memory_kill=0
  [[ -n "$kill_kb" ]] && memory_kill=1

  echo "${label}_rc=$rc"
  echo "${label}_run_safe_exit=${exit_code:-missing}"
  echo "${label}_peak_rss_bytes=${peak_bytes:-0}"
  echo "${label}_peak_rss_mb=$peak_mb"
  echo "${label}_memory_kill=$memory_kill"
  echo "${label}_memory_kill_kb=${kill_kb:-0}"
  echo "${label}_log=$log"
}

read_metric() {
  local key="$1"
  local file="$2"
  awk -F= -v k="$key" '$1 == k { print $2; exit }' "$file"
}

SUMMARY="$TMP_DIR/subphase_summary.out"
{
  run_stop_probe "stage1_mir_summary" "$STAGE1_PATH" "ADAMAS_STOP_AFTER_MIR"
  run_stop_probe "s2_hir_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_HIR"
  run_stop_probe "s2_mir_type_registration_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_MIR_TYPE_REGISTRATION"
  run_stop_probe "s2_mir_prepare_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_MIR_PREPARE"
  run_stop_probe "s2_mir_bodies_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_MIR_BODIES"
  run_stop_probe "s2_mir_opt_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_MIR_OPT"
  run_stop_probe "s2_mir_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_MIR"
} >"$SUMMARY"

emit_prefixed_summary() {
  local prefix="$1"
  local source_prefix="$2"
  awk -F= -v p="$prefix" -v s="$source_prefix" '
    index($1, s "_") == 1 {
      key = substr($1, length(s) + 2)
      print p "_" key "=" $2
    }
  ' "$SUMMARY"
}

emit_prefixed_summary "stage1_mir" "stage1_mir_summary"
emit_prefixed_summary "s2_hir" "s2_hir_summary"
emit_prefixed_summary "s2_mir_type_registration" "s2_mir_type_registration_summary"
emit_prefixed_summary "s2_mir_prepare" "s2_mir_prepare_summary"
emit_prefixed_summary "s2_mir_bodies" "s2_mir_bodies_summary"
emit_prefixed_summary "s2_mir_opt" "s2_mir_opt_summary"
emit_prefixed_summary "s2_mir" "s2_mir_summary"

metric_prefixes=(
  stage1_mir_summary
  s2_hir_summary
  s2_mir_type_registration_summary
  s2_mir_prepare_summary
  s2_mir_bodies_summary
  s2_mir_opt_summary
  s2_mir_summary
)

for prefix in "${metric_prefixes[@]}"; do
  eval "${prefix}_rc=\"$(read_metric "${prefix}_rc" "$SUMMARY")\""
  eval "${prefix}_peak=\"$(read_metric "${prefix}_peak_rss_mb" "$SUMMARY")\""
  eval "${prefix}_kill=\"$(read_metric "${prefix}_memory_kill" "$SUMMARY")\""
done

probe_bad() {
  local rc="$1"
  local peak="$2"
  local kill="$3"
  [[ "${rc:-99}" -ne 0 || "${kill:-1}" == "1" || "${peak:-999999}" -ge "$HIGH_RSS_MB" ]]
}

probe_clean() {
  local rc="$1"
  local peak="$2"
  local kill="$3"
  [[ "${rc:-99}" -eq 0 && "${kill:-1}" == "0" && "${peak:-999999}" -lt "$HIGH_RSS_MB" ]]
}

nested_classification="$(value_of_file classification "$CLASSIFIER_OUT")"
nested_default_memory_kill="$(value_of_file default_workers_memory_kill "$CLASSIFIER_OUT")"
nested_workers1_memory_kill="$(value_of_file workers1_memory_kill "$CLASSIFIER_OUT")"
nested_default_after_lower_main="$(value_of_file default_workers_after_lower_main "$CLASSIFIER_OUT")"
nested_workers1_after_lower_main="$(value_of_file workers1_after_lower_main "$CLASSIFIER_OUT")"

classification="workers1_mir_subphase_clean"
if probe_bad "${stage1_mir_summary_rc:-99}" "${stage1_mir_summary_peak:-999999}" "${stage1_mir_summary_kill:-1}"; then
  classification="workers1_mir_subphase_stage1_control_high"
elif probe_bad "${s2_hir_summary_rc:-99}" "${s2_hir_summary_peak:-999999}" "${s2_hir_summary_kill:-1}"; then
  classification="workers1_hir_resource_boundary"
elif probe_bad "${s2_mir_type_registration_summary_rc:-99}" "${s2_mir_type_registration_summary_peak:-999999}" "${s2_mir_type_registration_summary_kill:-1}"; then
  classification="workers1_mir_type_registration_resource_boundary"
elif probe_bad "${s2_mir_prepare_summary_rc:-99}" "${s2_mir_prepare_summary_peak:-999999}" "${s2_mir_prepare_summary_kill:-1}"; then
  classification="workers1_mir_prepare_resource_boundary"
elif probe_bad "${s2_mir_bodies_summary_rc:-99}" "${s2_mir_bodies_summary_peak:-999999}" "${s2_mir_bodies_summary_kill:-1}"; then
  classification="select_workers1_mir_body_lowering_resource_lane"
elif probe_bad "${s2_mir_opt_summary_rc:-99}" "${s2_mir_opt_summary_peak:-999999}" "${s2_mir_opt_summary_kill:-1}"; then
  classification="select_workers1_mir_optimization_resource_lane"
elif probe_bad "${s2_mir_summary_rc:-99}" "${s2_mir_summary_peak:-999999}" "${s2_mir_summary_kill:-1}"; then
  classification="workers1_mir_after_optimization_resource_boundary"
fi

echo "entry_classifier_rc=$entry_rc"
echo "nested.classification=$nested_classification"
echo "nested.default_workers_after_lower_main=$nested_default_after_lower_main"
echo "nested.default_workers_memory_kill=$nested_default_memory_kill"
echo "nested.workers1_after_lower_main=$nested_workers1_after_lower_main"
echo "nested.workers1_memory_kill=$nested_workers1_memory_kill"
echo "classification=$classification"
echo "entry_classifier_log=$CLASSIFIER_OUT"

if [[ "${REQUIRE_CLASSIFICATION:-0}" == "1" ]]; then
  case "$classification" in
    workers1_hir_resource_boundary|workers1_mir_type_registration_resource_boundary|workers1_mir_prepare_resource_boundary|select_workers1_mir_body_lowering_resource_lane|select_workers1_mir_optimization_resource_lane|workers1_mir_after_optimization_resource_boundary|workers1_mir_subphase_clean|workers1_mir_subphase_stage1_control_high)
      ;;
    *)
      exit 9
      ;;
  esac
fi

if [[ "${REQUIRE_SUBPHASE:-0}" == "1" ]]; then
  case "$classification" in
    select_workers1_mir_body_lowering_resource_lane|select_workers1_mir_optimization_resource_lane|workers1_mir_type_registration_resource_boundary|workers1_mir_prepare_resource_boundary|workers1_mir_after_optimization_resource_boundary|workers1_mir_subphase_clean)
      ;;
    *)
      exit 9
      ;;
  esac
fi
