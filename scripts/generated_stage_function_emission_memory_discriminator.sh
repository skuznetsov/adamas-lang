#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_function_emission_memory_discriminator.sh [source.cr]

Runs the generated-stage transaction report with the existing LLVM memory
snapshot instrumentation enabled, then parses the produced default-worker log
and a stage1 workers=1 control run.

This is a Slice 0k-DP discriminator for the default-mode function-emission
resource residual. It distinguishes incremental function-output/state growth
from pre-existing produced-stage non-GC pressure that is already high by the
first sequential function-emission snapshot.

Environment:
  KEEP_TMP=1             Keep temp dirs for manual inspection.
  REQUIRE_CURRENT=1      Exit nonzero unless the current pre-existing non-GC
                         pressure classification reproduces.
  TAIL_LINES             Tail lines passed to the transaction report
                         (default: 80).
  SMOKE_TIMEOUT          Produced-s2 compile timeout (default: 120).
  SMOKE_MEM_MB           Produced-s2 compile memory limit (default: 4096).

Classifications:
  function_emission_preexisting_non_gc_pressure
  function_emission_incremental_output_growth
  function_emission_snapshot_missing
  function_emission_stage1_control_failed
  function_emission_memory_drift
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-function-memory.XXXXXX")"
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
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-120}"
SMOKE_MEM_MB="${SMOKE_MEM_MB:-4096}"
REPORT_LOG="$TMP_DIR/transaction_report.out"
CONTROL_LOG="$TMP_DIR/stage1_workers1_control.log"
CONTROL_RUN_LOG="$TMP_DIR/stage1_workers1_control_run.log"

echo "# Generated Stage Function-Emission Memory Discriminator"
echo "repo=$ROOT_DIR"
echo "tail_lines=$TAIL_LINES"
echo "smoke_timeout=$SMOKE_TIMEOUT"
echo "smoke_mem_mb=$SMOKE_MEM_MB"
echo "require_current=${REQUIRE_CURRENT:-0}"

set +e
ADAMAS_LLVM_MEM_SNAPSHOT_EVERY=10 \
ADAMAS_LLVM_MEM_DETAIL=1 \
ADAMAS_LLVM_HASH_STRUCT_DETAIL=1 \
ADAMAS_LLVM_FUNC_STATE_STRUCT=1 \
ADAMAS_LLVM_MODULE_STRUCT=1 \
ADAMAS_LLVM_EMIT_TEXT_DETAIL=1 \
ADAMAS_LLVM_NAME_CHURN_DETAIL=1 \
KEEP_TMP=1 \
TAIL_LINES="$TAIL_LINES" \
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

report_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, index($0, "=") + 1); found = 1; exit } END { if (!found) exit 1 }' "$REPORT_LOG" 2>/dev/null || true
}

DEFAULT_LOG="$CLASSIFIER_TMP/default_workers_compile.log"
WORKERS1_LOG="$CLASSIFIER_TMP/workers1_compile.log"
SOURCE_PATH="$(report_value "invocation.source")"
STAGE1_PATH="$(report_value "invocation.stage1")"

echo "report_rc=$report_rc"
echo "report.final_classification=$(report_value "final_classification")"
echo "report.default_mode_boundary=$(report_value "resource.default_mode_boundary")"
echo "report.workers1_mode_boundary=$(report_value "resource.workers1_mode_boundary")"
echo "report.default_memory_kill=$(report_value "resource.default_memory_kill")"
echo "report.default_function_emission_last_index=$(report_value "resource.default_function_emission_last_index")"
echo "report.default_function_emission_last_total=$(report_value "resource.function_emission_last_total")"
echo "report.default_parallel_rand=$(report_value "worker_plan.default_parallel_rand")"

snapshot_summary() {
  local file="$1"
  awk '
    function field(name,   i,a) {
      for (i = 1; i <= NF; i++) {
        split($i, a, "=")
        if (a[1] == name) return a[2]
      }
      return ""
    }
    /\[LLVM_MEM\]/ {
      idx = field("idx")
      split(idx, idx_parts, "/")
      row_count++
      if (row_count == 1) {
        first_idx = idx_parts[1] + 0
        first_total = idx_parts[2] + 0
        first_non_gc = field("non_gc") + 0
        first_emit_raw_out = field("emit_raw_out") + 0
        first_func_state = field("func_state_struct_total") + 0
        first_mir_struct = field("mir_struct_total") + 0
      }
      last_idx = idx_parts[1] + 0
      last_total = idx_parts[2] + 0
      last_non_gc = field("non_gc") + 0
      last_emit_raw_out = field("emit_raw_out") + 0
      last_func_state = field("func_state_struct_total") + 0
      last_mir_struct = field("mir_struct_total") + 0
      last_emitted = field("emitted") + 0
      last_called = field("called") + 0
      last_undef = field("undef_ext") + 0
    }
    END {
      print "rows=" (row_count + 0)
      print "first_idx=" (first_idx + 0)
      print "first_total=" (first_total + 0)
      print "first_non_gc=" (first_non_gc + 0)
      print "first_emit_raw_out=" (first_emit_raw_out + 0)
      print "first_func_state=" (first_func_state + 0)
      print "first_mir_struct=" (first_mir_struct + 0)
      print "last_idx=" (last_idx + 0)
      print "last_total=" (last_total + 0)
      print "last_non_gc=" (last_non_gc + 0)
      print "last_emit_raw_out=" (last_emit_raw_out + 0)
      print "last_func_state=" (last_func_state + 0)
      print "last_mir_struct=" (last_mir_struct + 0)
      print "last_emitted=" (last_emitted + 0)
      print "last_called=" (last_called + 0)
      print "last_undef=" (last_undef + 0)
    }
  ' "$file"
}

get_summary_value() {
  local key="$1"
  local file="$2"
  awk -F= -v k="$key" '$1 == k { print $2; exit }' "$file"
}

DEFAULT_SUMMARY="$TMP_DIR/default_snapshot.summary"
CONTROL_SUMMARY="$TMP_DIR/stage1_control.summary"

if [[ -f "$DEFAULT_LOG" ]]; then
  snapshot_summary "$DEFAULT_LOG" >"$DEFAULT_SUMMARY"
else
  : >"$DEFAULT_SUMMARY"
fi

default_rows="$(get_summary_value rows "$DEFAULT_SUMMARY")"
default_first_non_gc="$(get_summary_value first_non_gc "$DEFAULT_SUMMARY")"
default_last_non_gc="$(get_summary_value last_non_gc "$DEFAULT_SUMMARY")"
default_first_emit_raw_out="$(get_summary_value first_emit_raw_out "$DEFAULT_SUMMARY")"
default_last_emit_raw_out="$(get_summary_value last_emit_raw_out "$DEFAULT_SUMMARY")"
default_first_func_state="$(get_summary_value first_func_state "$DEFAULT_SUMMARY")"
default_last_func_state="$(get_summary_value last_func_state "$DEFAULT_SUMMARY")"
default_first_idx="$(get_summary_value first_idx "$DEFAULT_SUMMARY")"
default_last_idx="$(get_summary_value last_idx "$DEFAULT_SUMMARY")"
default_last_total="$(get_summary_value last_total "$DEFAULT_SUMMARY")"

echo "default_snapshot_rows=${default_rows:-0}"
echo "default_first_idx=${default_first_idx:-0}"
echo "default_last_idx=${default_last_idx:-0}"
echo "default_last_total=${default_last_total:-0}"
echo "default_first_non_gc=${default_first_non_gc:-0}"
echo "default_last_non_gc=${default_last_non_gc:-0}"
echo "default_first_emit_raw_out=${default_first_emit_raw_out:-0}"
echo "default_last_emit_raw_out=${default_last_emit_raw_out:-0}"
echo "default_first_func_state=${default_first_func_state:-0}"
echo "default_last_func_state=${default_last_func_state:-0}"

stage1_control_rc=99
stage1_control_run_rc=99
if [[ -x "$STAGE1_PATH" && -f "$SOURCE_PATH" ]]; then
  CONTROL_BIN="$TMP_DIR/stage1_workers1_control_bin"
  set +e
  ADAMAS_LLVM_WORKERS=1 \
  ADAMAS_LLVM_MEM_SNAPSHOT_EVERY=10 \
  ADAMAS_LLVM_MEM_DETAIL=1 \
  ADAMAS_LLVM_HASH_STRUCT_DETAIL=1 \
  ADAMAS_LLVM_FUNC_STATE_STRUCT=1 \
  ADAMAS_LLVM_MODULE_STRUCT=1 \
  ADAMAS_LLVM_EMIT_TEXT_DETAIL=1 \
  ADAMAS_LLVM_NAME_CHURN_DETAIL=1 \
    "$ROOT_DIR/scripts/run_safe.sh" "$STAGE1_PATH" 120 4096 "$SOURCE_PATH" -o "$CONTROL_BIN" >"$CONTROL_LOG" 2>&1
  stage1_control_rc=$?
  set -e
  snapshot_summary "$CONTROL_LOG" >"$CONTROL_SUMMARY"

  if [[ "$stage1_control_rc" -eq 0 && -x "$CONTROL_BIN" ]]; then
    set +e
    "$ROOT_DIR/scripts/run_safe.sh" "$CONTROL_BIN" 5 512 >"$CONTROL_RUN_LOG" 2>&1
    stage1_control_run_rc=$?
    set -e
  fi
else
  : >"$CONTROL_SUMMARY"
fi

stage1_rows="$(get_summary_value rows "$CONTROL_SUMMARY")"
stage1_first_non_gc="$(get_summary_value first_non_gc "$CONTROL_SUMMARY")"
stage1_last_non_gc="$(get_summary_value last_non_gc "$CONTROL_SUMMARY")"
stage1_first_emit_raw_out="$(get_summary_value first_emit_raw_out "$CONTROL_SUMMARY")"
stage1_last_emit_raw_out="$(get_summary_value last_emit_raw_out "$CONTROL_SUMMARY")"
stage1_last_total="$(get_summary_value last_total "$CONTROL_SUMMARY")"

echo "stage1_control_rc=$stage1_control_rc"
echo "stage1_control_run_rc=$stage1_control_run_rc"
echo "stage1_control_stdout=$(awk '/^=== STDOUT ===$/ { capture = 1; next } /^=== STDERR ===$/ { capture = 0 } capture { print }' "$CONTROL_RUN_LOG" 2>/dev/null | paste -sd '|' -)"
echo "stage1_snapshot_rows=${stage1_rows:-0}"
echo "stage1_first_non_gc=${stage1_first_non_gc:-0}"
echo "stage1_last_non_gc=${stage1_last_non_gc:-0}"
echo "stage1_first_emit_raw_out=${stage1_first_emit_raw_out:-0}"
echo "stage1_last_emit_raw_out=${stage1_last_emit_raw_out:-0}"
echo "stage1_last_total=${stage1_last_total:-0}"

classification="function_emission_memory_drift"
if [[ "${default_rows:-0}" == "0" ]]; then
  classification="function_emission_snapshot_missing"
elif [[ "$stage1_control_rc" -ne 0 || "$stage1_control_run_rc" -ne 0 || "${stage1_rows:-0}" == "0" ]]; then
  classification="function_emission_stage1_control_failed"
elif [[ "${default_first_non_gc:-0}" -ge 1000000000 &&
        "${default_first_idx:-0}" -le 15 &&
        "${default_last_idx:-0}" -le 90 &&
        "${stage1_first_non_gc:-0}" -eq 0 &&
        "$(report_value "resource.default_memory_kill")" == "1" ]]; then
  classification="function_emission_preexisting_non_gc_pressure"
elif [[ "${default_first_non_gc:-0}" -lt 1000000000 &&
        "${default_last_emit_raw_out:-0}" -gt $(( ${default_first_emit_raw_out:-0} + 100000000 )) ]]; then
  classification="function_emission_incremental_output_growth"
fi

echo "classification=$classification"
echo "report_log=$REPORT_LOG"
echo "default_workers_log=$DEFAULT_LOG"
echo "workers1_log=$WORKERS1_LOG"
echo "stage1_control_log=$CONTROL_LOG"

if [[ "$classification" != "function_emission_preexisting_non_gc_pressure" || "${TAIL_ALWAYS:-0}" == "1" ]]; then
  echo "report_tail:"
  tail -120 "$REPORT_LOG" || true
  if [[ -f "$DEFAULT_LOG" ]]; then
    echo "default_workers_tail:"
    tail -120 "$DEFAULT_LOG" || true
  fi
  if [[ -f "$CONTROL_LOG" ]]; then
    echo "stage1_control_tail:"
    tail -80 "$CONTROL_LOG" || true
  fi
fi

if [[ "${REQUIRE_CURRENT:-0}" == "1" && "$classification" != "function_emission_preexisting_non_gc_pressure" ]]; then
  exit 9
fi
