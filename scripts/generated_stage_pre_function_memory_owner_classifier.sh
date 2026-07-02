#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_pre_function_memory_owner_classifier.sh [source.cr]

Runs the strict generated-stage transaction report with default-off memory.phase
rows enabled, then runs a stage1 workers=1 control on the same source.

This is a Slice 0k-DQ owner selector for the current default-worker
function-emission resource residual. It classifies where produced-stage non-GC
pressure first becomes high before/at LLVM function emission.

Environment:
  KEEP_TMP=1             Keep temp dirs for manual inspection.
  REQUIRE_OWNER=1        Exit nonzero unless the run produces an owner
                         classification rather than missing/drift/control-fail.
  TAIL_LINES             Tail lines passed to the transaction report
                         (default: 80).
  STAGE2_BUILD_TIMEOUT   run_safe timeout for building generated s2
                         (default: 600).
  SMOKE_TIMEOUT          Produced-s2 compile timeout (default: 120).
  SMOKE_MEM_MB           Produced-s2 compile memory limit (default: 4096).
  HIGH_NON_GC_BYTES      Threshold for "high" non-GC pressure
                         (default: 1000000000).

Classifications:
  pre_function_pressure_hir_owned
  pre_function_pressure_escape_owned
  pre_function_pressure_mir_owned
  pre_function_pressure_llvm_generator_entry
  pre_function_pressure_llvm_setup_owned
  pre_function_pressure_llvm_session_owned
  pre_function_pressure_function_emission_entry
  pre_function_pressure_low_until_snapshot
  pre_function_memory_phase_missing
  pre_function_stage1_control_failed
  pre_function_memory_drift
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-pre-function-memory.XXXXXX")"
REPORT_TMP=""
CLASSIFIER_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
    [[ -n "$REPORT_TMP" ]] && echo "kept_report_tmp=$REPORT_TMP"
    [[ -n "$CLASSIFIER_TMP" ]] && echo "kept_classifier_tmp=$CLASSIFIER_TMP"
  else
    [[ -n "$REPORT_TMP" && "$REPORT_TMP" == "$ROOT_DIR/tmp/generated-stage-execution-tx."* ]] && rm -rf "$REPORT_TMP"
    [[ -n "$CLASSIFIER_TMP" && "$CLASSIFIER_TMP" == "$ROOT_DIR/tmp/generated-stage-llvm-entry."* ]] && rm -rf "$CLASSIFIER_TMP"
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

TAIL_LINES="${TAIL_LINES:-80}"
STAGE2_BUILD_TIMEOUT="${STAGE2_BUILD_TIMEOUT:-600}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-120}"
SMOKE_MEM_MB="${SMOKE_MEM_MB:-4096}"
HIGH_NON_GC_BYTES="${HIGH_NON_GC_BYTES:-1000000000}"
REPORT_LOG="$TMP_DIR/transaction_report.out"
STAGE1_LEDGER="$TMP_DIR/stage1_memory_ledger.tsv"
STAGE1_LOG="$TMP_DIR/stage1_workers1_control.log"
STAGE1_RUN_LOG="$TMP_DIR/stage1_workers1_control_run.log"

echo "# Generated Stage Pre-Function Memory Owner Classifier"
echo "repo=$ROOT_DIR"
echo "tail_lines=$TAIL_LINES"
echo "stage2_build_timeout=$STAGE2_BUILD_TIMEOUT"
echo "smoke_timeout=$SMOKE_TIMEOUT"
echo "smoke_mem_mb=$SMOKE_MEM_MB"
echo "high_non_gc_bytes=$HIGH_NON_GC_BYTES"
echo "require_owner=${REQUIRE_OWNER:-0}"

set +e
ADAMAS_GSETX_MEMORY_PHASES=1 \
KEEP_TMP=1 \
TAIL_LINES="$TAIL_LINES" \
STAGE2_BUILD_TIMEOUT="$STAGE2_BUILD_TIMEOUT" \
SMOKE_TIMEOUT="$SMOKE_TIMEOUT" \
SMOKE_MEM_MB="$SMOKE_MEM_MB" \
REQUIRE_JOINED=1 \
REQUIRE_POST_CU_RESOURCE=1 \
REQUIRE_RESOURCE_PHASE_SPLIT=1 \
REQUIRE_FUNCTION_EMISSION_SPLIT=1 \
REQUIRE_WORKER_MODE_BOUNDARY=1 \
  "$ROOT_DIR/scripts/generated_stage_execution_transaction_report.sh" "$@" >"$REPORT_LOG" 2>&1
report_rc=$?
set -e

REPORT_TMP="$(awk -F= '$1 == "kept_tmp" { print $2; exit }' "$REPORT_LOG" 2>/dev/null || true)"
CLASSIFIER_TMP="$(awk -F= '$1 == "kept_classifier_tmp" { print $2; exit }' "$REPORT_LOG" 2>/dev/null || true)"
RUNTIME_LEDGER="$REPORT_TMP/runtime_ledger.tsv"

report_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, index($0, "=") + 1); found = 1; exit } END { if (!found) exit 1 }' "$REPORT_LOG" 2>/dev/null || true
}

memory_summary() {
  local ledger="$1"
  local mode="$2"
  awk -F'\t' -v mode="$mode" -v high="$HIGH_NON_GC_BYTES" '
    function field(name,   i,n,j,parts,row_phase,value) {
      value = ""
      for (i = 5; i <= NF; i++) {
        n = split($i, parts, " ")
        for (j = 1; j <= n; j++) {
          if (index(parts[j], name "=") == 1) {
            value = substr(parts[j], length(name) + 2)
          }
        }
      }
      return value
    }
    $1 == "GSETX" && $3 == mode && $4 == "memory.phase" {
      rows++
      phase = field("phase")
      owner = field("owner")
      non_gc = field("non_gc") + 0
      if (rows == 1) {
        first_phase = phase
        first_owner = owner
        first_non_gc = non_gc
      }
      if (non_gc > max_non_gc) {
        max_non_gc = non_gc
        max_phase = phase
        max_owner = owner
      }
      if (!first_high_seen && non_gc >= high) {
        first_high_seen = 1
        first_high_phase = phase
        first_high_owner = owner
        first_high_non_gc = non_gc
      }
      last_phase = phase
      last_owner = owner
      last_non_gc = non_gc
    }
    END {
      print "rows=" (rows + 0)
      print "first_phase=" first_phase
      print "first_owner=" first_owner
      print "first_non_gc=" (first_non_gc + 0)
      print "first_high_phase=" first_high_phase
      print "first_high_owner=" first_high_owner
      print "first_high_non_gc=" (first_high_non_gc + 0)
      print "max_phase=" max_phase
      print "max_owner=" max_owner
      print "max_non_gc=" (max_non_gc + 0)
      print "last_phase=" last_phase
      print "last_owner=" last_owner
      print "last_non_gc=" (last_non_gc + 0)
    }
  ' "$ledger"
}

get_summary_value() {
  local key="$1"
  local file="$2"
  awk -F= -v k="$key" '$1 == k { print $2; exit }' "$file"
}

classify_phase() {
  local phase="$1"
  case "$phase" in
    cli.hir_final|cli.hir_after_rta)
      echo "pre_function_pressure_hir_owned"
      ;;
    cli.escape_done)
      echo "pre_function_pressure_escape_owned"
      ;;
    cli.mir_lowering_new|cli.mir_type_registration_done|cli.mir_prepare_done|cli.mir_bodies_lowered|cli.mir_opt_done|cli.mir_opt_deferred|cli.mir_opt_disabled|cli.mir_final)
      echo "pre_function_pressure_mir_owned"
      ;;
    cli.llvm_generator_new|cli.llvm_generate_call_start|llvm.initialize_done|llvm.generate_start)
      echo "pre_function_pressure_llvm_generator_entry"
      ;;
    llvm.prelude_emit_done)
      echo "pre_function_pressure_llvm_setup_owned"
      ;;
    llvm.session_built|llvm.function_emission_start)
      echo "pre_function_pressure_llvm_session_owned"
      ;;
    llvm.sequential_start)
      echo "pre_function_pressure_function_emission_entry"
      ;;
    "")
      echo "pre_function_pressure_low_until_snapshot"
      ;;
    *)
      echo "pre_function_memory_drift"
      ;;
  esac
}

DEFAULT_SUMMARY="$TMP_DIR/default_memory.summary"
STAGE1_SUMMARY="$TMP_DIR/stage1_memory.summary"

if [[ -f "$RUNTIME_LEDGER" ]]; then
  memory_summary "$RUNTIME_LEDGER" "default_workers" >"$DEFAULT_SUMMARY"
else
  : >"$DEFAULT_SUMMARY"
fi

SOURCE_PATH="$(report_value "invocation.source")"
STAGE1_PATH="$(report_value "invocation.stage1")"

stage1_control_rc=99
stage1_control_run_rc=99
if [[ -x "$STAGE1_PATH" && -f "$SOURCE_PATH" ]]; then
  STAGE1_BIN="$TMP_DIR/stage1_workers1_control_bin"
  set +e
  ADAMAS_GSETX_ID="stage1_memory_control" \
  ADAMAS_GSETX_LEDGER="$STAGE1_LEDGER" \
  ADAMAS_GSETX_RUN_MODE=stage1_workers1 \
  ADAMAS_GSETX_MEMORY_PHASES=1 \
  ADAMAS_LLVM_WORKERS=1 \
    "$ROOT_DIR/scripts/run_safe.sh" "$STAGE1_PATH" 120 4096 "$SOURCE_PATH" -o "$STAGE1_BIN" >"$STAGE1_LOG" 2>&1
  stage1_control_rc=$?
  set -e
  if [[ "$stage1_control_rc" -eq 0 && -x "$STAGE1_BIN" ]]; then
    set +e
    "$ROOT_DIR/scripts/run_safe.sh" "$STAGE1_BIN" 5 512 >"$STAGE1_RUN_LOG" 2>&1
    stage1_control_run_rc=$?
    set -e
  fi
  if [[ -f "$STAGE1_LEDGER" ]]; then
    memory_summary "$STAGE1_LEDGER" "stage1_workers1" >"$STAGE1_SUMMARY"
  else
    : >"$STAGE1_SUMMARY"
  fi
else
  : >"$STAGE1_SUMMARY"
fi

default_rows="$(get_summary_value rows "$DEFAULT_SUMMARY")"
default_first_phase="$(get_summary_value first_phase "$DEFAULT_SUMMARY")"
default_first_non_gc="$(get_summary_value first_non_gc "$DEFAULT_SUMMARY")"
default_first_high_phase="$(get_summary_value first_high_phase "$DEFAULT_SUMMARY")"
default_first_high_owner="$(get_summary_value first_high_owner "$DEFAULT_SUMMARY")"
default_first_high_non_gc="$(get_summary_value first_high_non_gc "$DEFAULT_SUMMARY")"
default_max_phase="$(get_summary_value max_phase "$DEFAULT_SUMMARY")"
default_max_non_gc="$(get_summary_value max_non_gc "$DEFAULT_SUMMARY")"
default_last_phase="$(get_summary_value last_phase "$DEFAULT_SUMMARY")"
default_last_non_gc="$(get_summary_value last_non_gc "$DEFAULT_SUMMARY")"

stage1_rows="$(get_summary_value rows "$STAGE1_SUMMARY")"
stage1_first_high_phase="$(get_summary_value first_high_phase "$STAGE1_SUMMARY")"
stage1_max_phase="$(get_summary_value max_phase "$STAGE1_SUMMARY")"
stage1_max_non_gc="$(get_summary_value max_non_gc "$STAGE1_SUMMARY")"
stage1_last_phase="$(get_summary_value last_phase "$STAGE1_SUMMARY")"
stage1_last_non_gc="$(get_summary_value last_non_gc "$STAGE1_SUMMARY")"

classification="pre_function_memory_drift"
if [[ "${default_rows:-0}" == "0" ]]; then
  classification="pre_function_memory_phase_missing"
elif [[ "$stage1_control_rc" -ne 0 || "$stage1_control_run_rc" -ne 0 || "${stage1_rows:-0}" == "0" ]]; then
  classification="pre_function_stage1_control_failed"
elif [[ "${stage1_max_non_gc:-0}" -ge "$HIGH_NON_GC_BYTES" ]]; then
  classification="pre_function_memory_drift"
else
  classification="$(classify_phase "${default_first_high_phase:-}")"
fi

echo "report_rc=$report_rc"
echo "report.final_classification=$(report_value "final_classification")"
echo "report.default_mode_boundary=$(report_value "resource.default_mode_boundary")"
echo "report.workers1_mode_boundary=$(report_value "resource.workers1_mode_boundary")"
echo "report.default_memory_kill=$(report_value "resource.default_memory_kill")"
echo "report.default_function_emission_last_index=$(report_value "resource.default_function_emission_last_index")"
echo "report.default_function_emission_last_total=$(report_value "resource.function_emission_last_total")"
echo "default_memory_rows=${default_rows:-0}"
echo "default_first_phase=${default_first_phase:-}"
echo "default_first_non_gc=${default_first_non_gc:-0}"
echo "default_first_high_phase=${default_first_high_phase:-}"
echo "default_first_high_owner=${default_first_high_owner:-}"
echo "default_first_high_non_gc=${default_first_high_non_gc:-0}"
echo "default_max_phase=${default_max_phase:-}"
echo "default_max_non_gc=${default_max_non_gc:-0}"
echo "default_last_phase=${default_last_phase:-}"
echo "default_last_non_gc=${default_last_non_gc:-0}"
echo "stage1_control_rc=$stage1_control_rc"
echo "stage1_control_run_rc=$stage1_control_run_rc"
echo "stage1_control_stdout=$(awk '/^=== STDOUT ===$/ { capture = 1; next } /^=== STDERR ===$/ { capture = 0 } capture { print }' "$STAGE1_RUN_LOG" 2>/dev/null | paste -sd '|' -)"
echo "stage1_memory_rows=${stage1_rows:-0}"
echo "stage1_first_high_phase=${stage1_first_high_phase:-}"
echo "stage1_max_phase=${stage1_max_phase:-}"
echo "stage1_max_non_gc=${stage1_max_non_gc:-0}"
echo "stage1_last_phase=${stage1_last_phase:-}"
echo "stage1_last_non_gc=${stage1_last_non_gc:-0}"
echo "classification=$classification"
echo "report_log=$REPORT_LOG"
echo "runtime_ledger=$RUNTIME_LEDGER"
echo "stage1_ledger=$STAGE1_LEDGER"
echo "stage1_control_log=$STAGE1_LOG"

if [[ "$classification" == "pre_function_memory_phase_missing" ||
      "$classification" == "pre_function_stage1_control_failed" ||
      "$classification" == "pre_function_memory_drift" ||
      "${TAIL_ALWAYS:-0}" == "1" ]]; then
  echo "report_tail:"
  tail -120 "$REPORT_LOG" || true
  if [[ -f "$STAGE1_LOG" ]]; then
    echo "stage1_control_tail:"
    tail -80 "$STAGE1_LOG" || true
  fi
fi

if [[ "${REQUIRE_OWNER:-0}" == "1" ]]; then
  case "$classification" in
    pre_function_pressure_hir_owned|pre_function_pressure_escape_owned|pre_function_pressure_mir_owned|pre_function_pressure_llvm_generator_entry|pre_function_pressure_llvm_setup_owned|pre_function_pressure_llvm_session_owned|pre_function_pressure_function_emission_entry|pre_function_pressure_low_until_snapshot)
      ;;
    *)
      exit 9
      ;;
  esac
fi
