#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_mode_resource_lane_classifier.sh [source.cr]

Build/use a fresh generated s2 compiler, measure mode-specific OS RSS at HIR
and MIR stop gates, and join the result with the current generated-stage
transaction report.

This is the post-0k-DS mode-lane selector. It asks whether the next
GeneratedStageExecution resource slice should target the workers=1
HIR-to-MIR corridor or the default-worker late LLVM/function-emission corridor.
It does not use GC non_gc as an owner signal and does not admit worker-policy,
memory-budget, startup, parse, HIR, MIR, backend-rescue, NamedTuple/Tuple,
ambient-map, or BlockOwner changes.

Environment:
  KEEP_TMP=1                 Keep temp dirs for manual inspection.
  REQUIRE_CLASSIFICATION=1   Exit nonzero unless a terminal classification is
                             produced.
  REQUIRE_LANE_SELECTION=1   Exit nonzero unless a mode-local lane is selected
                             or the gate is clean.
  HIGH_RSS_MB                Peak RSS threshold for "high" (default: 3072).
  STAGE1_COMPILER            Pass-through to generated_stage_llvm_entry_classifier.
  GENERATED_S2               Pass-through to generated_stage_llvm_entry_classifier.
  STAGE1_MODE                Pass-through stage1 mode (default inherited).
  STAGE2_BUILD_TIMEOUT       Pass-through generated s2 build timeout.
  STAGE2_BUILD_MEM_MB        Pass-through generated s2 build RSS cap.
  SMOKE_TIMEOUT              Stop-gate compile timeout (default: 120).
  SMOKE_MEM_MB               Stop-gate compile RSS cap (default: 4096).
  TAIL_LINES                 Nested classifier tail lines (default: 50).

Classifications:
  select_workers1_hir_to_mir_resource_lane
  select_default_late_llvm_resource_lane
  workers1_hir_resource_boundary
  default_hir_resource_boundary
  default_hir_to_mir_resource_boundary
  post_mir_resource_boundary_unselected
  resource_gate_clean
  mode_resource_classifier_missing_time_l
  mode_resource_classifier_build_failed
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x /usr/bin/time ]]; then
  echo "classification=mode_resource_classifier_missing_time_l"
  echo "reason=/usr/bin/time_missing"
  exit 9
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-mode-resource.XXXXXX")"
NESTED_ENTRY_TMP=""
TX_TMP=""
TX_NESTED_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
    [[ -n "$NESTED_ENTRY_TMP" ]] && echo "kept_entry_tmp=$NESTED_ENTRY_TMP"
    [[ -n "$TX_TMP" ]] && echo "kept_transaction_tmp=$TX_TMP"
    [[ -n "$TX_NESTED_TMP" ]] && echo "kept_transaction_classifier_tmp=$TX_NESTED_TMP"
  else
    if [[ -n "$NESTED_ENTRY_TMP" && "$NESTED_ENTRY_TMP" == "$ROOT_DIR/tmp/generated-stage-llvm-entry."* ]]; then
      rm -rf "$NESTED_ENTRY_TMP"
    fi
    if [[ -n "$TX_TMP" && "$TX_TMP" == "$ROOT_DIR/tmp/generated-stage-execution-tx."* ]]; then
      rm -rf "$TX_TMP"
    fi
    if [[ -n "$TX_NESTED_TMP" && "$TX_NESTED_TMP" == "$ROOT_DIR/tmp/generated-stage-llvm-entry."* ]]; then
      rm -rf "$TX_NESTED_TMP"
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
TAIL_LINES="${TAIL_LINES:-50}"
ENTRY_OUT="$TMP_DIR/generated_stage_llvm_entry.out"
TX_OUT="$TMP_DIR/generated_stage_transaction.out"

echo "# Generated Stage Mode Resource Lane Classifier"
echo "repo=$ROOT_DIR"
echo "source=$SOURCE"
echo "high_rss_mb=$HIGH_RSS_MB"
echo "smoke_timeout=$SMOKE_TIMEOUT"
echo "smoke_mem_mb=$SMOKE_MEM_MB"
echo "require_classification=${REQUIRE_CLASSIFICATION:-0}"
echo "require_lane_selection=${REQUIRE_LANE_SELECTION:-0}"

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
  "$ROOT_DIR/scripts/generated_stage_llvm_entry_classifier.sh" "$SOURCE" >"$ENTRY_OUT" 2>&1
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

NESTED_ENTRY_TMP="$(value_of_file kept_tmp "$ENTRY_OUT")"
STAGE1_PATH="$(value_of_file stage1 "$ENTRY_OUT")"
S2_PATH="$(value_of_file generated_s2 "$ENTRY_OUT")"

if [[ "$entry_rc" -ne 0 || ! -x "$S2_PATH" ]]; then
  echo "entry_classifier_rc=$entry_rc"
  echo "nested.classification=$(value_of_file classification "$ENTRY_OUT")"
  echo "classification=mode_resource_classifier_build_failed"
  echo "entry_classifier_tail:"
  tail -120 "$ENTRY_OUT" || true
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
  local mode="$4"
  local out_bin="$TMP_DIR/${label}.out"
  local log="$TMP_DIR/${label}.log"

  set +e
  if [[ "$mode" == "workers1" ]]; then
    env "$stop_env=1" ADAMAS_LLVM_WORKERS=1 \
      /usr/bin/time -l "$ROOT_DIR/scripts/run_safe.sh" "$compiler" "$SMOKE_TIMEOUT" "$SMOKE_MEM_MB" \
        "$SOURCE" -o "$out_bin" >"$log" 2>&1
  else
    env "$stop_env=1" \
      /usr/bin/time -l "$ROOT_DIR/scripts/run_safe.sh" "$compiler" "$SMOKE_TIMEOUT" "$SMOKE_MEM_MB" \
        "$SOURCE" -o "$out_bin" >"$log" 2>&1
  fi
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

SUMMARY="$TMP_DIR/stop_probe_summary.out"
{
  run_stop_probe "stage1_workers1_mir_summary" "$STAGE1_PATH" "ADAMAS_STOP_AFTER_MIR" "workers1"
  run_stop_probe "s2_default_hir_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_HIR" "default"
  run_stop_probe "s2_workers1_hir_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_HIR" "workers1"
  run_stop_probe "s2_default_mir_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_MIR" "default"
  run_stop_probe "s2_workers1_mir_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_MIR" "workers1"
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

emit_prefixed_summary "stage1_workers1_mir" "stage1_workers1_mir_summary"
emit_prefixed_summary "s2_default_hir" "s2_default_hir_summary"
emit_prefixed_summary "s2_workers1_hir" "s2_workers1_hir_summary"
emit_prefixed_summary "s2_default_mir" "s2_default_mir_summary"
emit_prefixed_summary "s2_workers1_mir" "s2_workers1_mir_summary"

set +e
KEEP_TMP=1 \
STAGE1_COMPILER="$STAGE1_PATH" \
GENERATED_S2="$S2_PATH" \
SMOKE_TIMEOUT="$SMOKE_TIMEOUT" \
SMOKE_MEM_MB="$SMOKE_MEM_MB" \
TAIL_LINES="$TAIL_LINES" \
REQUIRE_JOINED=1 \
REQUIRE_POST_CU_RESOURCE=1 \
REQUIRE_RESOURCE_PHASE_SPLIT=1 \
REQUIRE_FUNCTION_EMISSION_SPLIT=1 \
REQUIRE_WORKER_MODE_BOUNDARY=1 \
  "$ROOT_DIR/scripts/generated_stage_execution_transaction_report.sh" "$SOURCE" >"$TX_OUT" 2>&1
tx_rc=$?
set -e

TX_TMP="$(value_of_file kept_tmp "$TX_OUT")"
TX_NESTED_TMP="$(value_of_file kept_classifier_tmp "$TX_OUT")"

stage1_workers1_mir_rc="$(read_metric stage1_workers1_mir_summary_rc "$SUMMARY")"
stage1_workers1_mir_peak="$(read_metric stage1_workers1_mir_summary_peak_rss_mb "$SUMMARY")"
stage1_workers1_mir_kill="$(read_metric stage1_workers1_mir_summary_memory_kill "$SUMMARY")"
s2_default_hir_rc="$(read_metric s2_default_hir_summary_rc "$SUMMARY")"
s2_default_hir_peak="$(read_metric s2_default_hir_summary_peak_rss_mb "$SUMMARY")"
s2_default_hir_kill="$(read_metric s2_default_hir_summary_memory_kill "$SUMMARY")"
s2_workers1_hir_rc="$(read_metric s2_workers1_hir_summary_rc "$SUMMARY")"
s2_workers1_hir_peak="$(read_metric s2_workers1_hir_summary_peak_rss_mb "$SUMMARY")"
s2_workers1_hir_kill="$(read_metric s2_workers1_hir_summary_memory_kill "$SUMMARY")"
s2_default_mir_rc="$(read_metric s2_default_mir_summary_rc "$SUMMARY")"
s2_default_mir_peak="$(read_metric s2_default_mir_summary_peak_rss_mb "$SUMMARY")"
s2_default_mir_kill="$(read_metric s2_default_mir_summary_memory_kill "$SUMMARY")"
s2_workers1_mir_rc="$(read_metric s2_workers1_mir_summary_rc "$SUMMARY")"
s2_workers1_mir_peak="$(read_metric s2_workers1_mir_summary_peak_rss_mb "$SUMMARY")"
s2_workers1_mir_kill="$(read_metric s2_workers1_mir_summary_memory_kill "$SUMMARY")"

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

nested_classification="$(value_of_file classification "$ENTRY_OUT")"
nested_default_memory_kill="$(value_of_file default_workers_memory_kill "$ENTRY_OUT")"
nested_workers1_memory_kill="$(value_of_file workers1_memory_kill "$ENTRY_OUT")"
nested_default_after_lower_main="$(value_of_file default_workers_after_lower_main "$ENTRY_OUT")"
nested_workers1_after_lower_main="$(value_of_file workers1_after_lower_main "$ENTRY_OUT")"
tx_final_classification="$(value_of_file final_classification "$TX_OUT")"
tx_join_status="$(value_of_file join_status "$TX_OUT")"
tx_default_boundary="$(value_of_file resource.default_mode_boundary "$TX_OUT")"
tx_workers1_boundary="$(value_of_file resource.workers1_mode_boundary "$TX_OUT")"
tx_default_function_rows="$(value_of_file runtime.default_function_emission_phase_rows "$TX_OUT")"
tx_workers1_function_rows="$(value_of_file runtime.workers1_function_emission_phase_rows "$TX_OUT")"
tx_default_function_outcome_rows="$(value_of_file runtime.default_function_emission_outcome_rows "$TX_OUT")"
tx_workers1_function_outcome_rows="$(value_of_file runtime.workers1_function_emission_outcome_rows "$TX_OUT")"
tx_last_function_outcome_status="$(value_of_file resource.function_emission_last_outcome_status "$TX_OUT")"
tx_last_function_outcome_index="$(value_of_file resource.function_emission_last_outcome_index "$TX_OUT")"
tx_last_function_outcome_function="$(value_of_file resource.function_emission_last_outcome_function "$TX_OUT")"
tx_default_memory_kill="$(value_of_file resource.default_memory_kill "$TX_OUT")"
tx_workers1_memory_kill="$(value_of_file resource.workers1_memory_kill "$TX_OUT")"

classification="post_mir_resource_boundary_unselected"
if probe_bad "$s2_workers1_hir_rc" "$s2_workers1_hir_peak" "$s2_workers1_hir_kill"; then
  classification="workers1_hir_resource_boundary"
elif probe_bad "$s2_default_hir_rc" "$s2_default_hir_peak" "$s2_default_hir_kill"; then
  classification="default_hir_resource_boundary"
elif probe_bad "$s2_workers1_mir_rc" "$s2_workers1_mir_peak" "$s2_workers1_mir_kill" &&
     probe_clean "$s2_default_mir_rc" "$s2_default_mir_peak" "$s2_default_mir_kill"; then
  classification="select_workers1_hir_to_mir_resource_lane"
elif probe_bad "$s2_default_mir_rc" "$s2_default_mir_peak" "$s2_default_mir_kill"; then
  classification="default_hir_to_mir_resource_boundary"
elif [[ "$nested_classification" == "clean_both_modes" ]]; then
  classification="resource_gate_clean"
elif probe_clean "$s2_default_mir_rc" "$s2_default_mir_peak" "$s2_default_mir_kill" &&
     probe_clean "$s2_workers1_mir_rc" "$s2_workers1_mir_peak" "$s2_workers1_mir_kill" &&
     [[ "$tx_default_boundary" == "reached_function_emission" &&
        "${tx_default_memory_kill:-0}" == "1" ]]; then
  classification="select_default_late_llvm_resource_lane"
fi

echo "entry_classifier_rc=$entry_rc"
echo "transaction_report_rc=$tx_rc"
echo "nested.classification=$nested_classification"
echo "nested.default_workers_after_lower_main=$nested_default_after_lower_main"
echo "nested.default_workers_memory_kill=$nested_default_memory_kill"
echo "nested.workers1_after_lower_main=$nested_workers1_after_lower_main"
echo "nested.workers1_memory_kill=$nested_workers1_memory_kill"
echo "transaction.final_classification=${tx_final_classification:-missing}"
echo "transaction.join_status=${tx_join_status:-missing}"
echo "transaction.default_mode_boundary=${tx_default_boundary:-missing}"
echo "transaction.workers1_mode_boundary=${tx_workers1_boundary:-missing}"
echo "transaction.default_function_emission_rows=${tx_default_function_rows:-missing}"
echo "transaction.workers1_function_emission_rows=${tx_workers1_function_rows:-missing}"
echo "transaction.default_function_emission_outcome_rows=${tx_default_function_outcome_rows:-missing}"
echo "transaction.workers1_function_emission_outcome_rows=${tx_workers1_function_outcome_rows:-missing}"
echo "transaction.last_function_emission_outcome_status=${tx_last_function_outcome_status:-missing}"
echo "transaction.last_function_emission_outcome_index=${tx_last_function_outcome_index:-missing}"
echo "transaction.last_function_emission_outcome_function=${tx_last_function_outcome_function:-missing}"
echo "transaction.default_memory_kill=${tx_default_memory_kill:-missing}"
echo "transaction.workers1_memory_kill=${tx_workers1_memory_kill:-missing}"
echo "classification=$classification"
echo "entry_classifier_log=$ENTRY_OUT"
echo "transaction_report_log=$TX_OUT"

if [[ "${REQUIRE_CLASSIFICATION:-0}" == "1" ]]; then
  case "$classification" in
    select_workers1_hir_to_mir_resource_lane|select_default_late_llvm_resource_lane|workers1_hir_resource_boundary|default_hir_resource_boundary|default_hir_to_mir_resource_boundary|post_mir_resource_boundary_unselected|resource_gate_clean)
      ;;
    *)
      exit 9
      ;;
  esac
fi

if [[ "${REQUIRE_LANE_SELECTION:-0}" == "1" ]]; then
  case "$classification" in
    select_workers1_hir_to_mir_resource_lane|select_default_late_llvm_resource_lane|resource_gate_clean)
      ;;
    *)
      exit 9
      ;;
  esac
fi
