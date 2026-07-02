#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_pre_hir_memory_split_classifier.sh [source.cr]

Runs the generated-stage pre-function memory owner classifier, then reclassifies
the default-worker memory.phase ledger using the finer pre-HIR phase rows.

This is the single admitted L9 selector after Slice 0k-DQ. It must terminate
the pre-HIR pressure question into a named owner edge, a lane refutation, a
board pivot, or an explicit impasse before another selector on this surface is
added.

Environment:
  KEEP_TMP=1             Keep temp dirs for manual inspection.
  REQUIRE_SPLIT=1        Exit nonzero unless the run produces a terminal
                         pre-HIR split classification.
  HIGH_NON_GC_BYTES      Threshold for "high" non-GC pressure
                         (default: 1000000000).
  TAIL_LINES             Tail lines passed to nested classifier (default: 80).
  STAGE2_BUILD_TIMEOUT   Nested generated s2 build timeout (default: 600).
  SMOKE_TIMEOUT          Nested produced-s2 compile timeout (default: 120).
  SMOKE_MEM_MB           Nested produced-s2 compile memory limit (default: 4096).

Terminal classifications:
  pre_hir_pressure_compile_entry
  pre_hir_pressure_parse_entry
  pre_hir_pressure_prelude_parse
  pre_hir_pressure_user_parse_or_source_retention
  pre_hir_pressure_semantic_prepass
  pre_hir_pressure_hir_setup
  pre_hir_pressure_hir_collect
  pre_hir_pressure_hir_type_registration
  pre_hir_pressure_hir_function_registration
  pre_hir_pressure_hir_layout_fixup
  pre_hir_pressure_lower_main
  pre_hir_pressure_pending_flush_or_final
  pre_hir_pressure_low_until_hir_final
  pre_hir_memory_phase_missing
  pre_hir_stage1_control_failed
  pre_hir_memory_drift
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-pre-hir-memory.XXXXXX")"
OWNER_LOG="$TMP_DIR/pre_function_owner.out"
NESTED_TMP=""
NESTED_REPORT_TMP=""
NESTED_CLASSIFIER_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
    [[ -n "$NESTED_TMP" ]] && echo "kept_nested_tmp=$NESTED_TMP"
    [[ -n "$NESTED_REPORT_TMP" ]] && echo "kept_nested_report_tmp=$NESTED_REPORT_TMP"
    [[ -n "$NESTED_CLASSIFIER_TMP" ]] && echo "kept_nested_classifier_tmp=$NESTED_CLASSIFIER_TMP"
  else
    [[ -n "$NESTED_REPORT_TMP" && "$NESTED_REPORT_TMP" == "$ROOT_DIR/tmp/generated-stage-execution-tx."* ]] && rm -rf "$NESTED_REPORT_TMP"
    [[ -n "$NESTED_CLASSIFIER_TMP" && "$NESTED_CLASSIFIER_TMP" == "$ROOT_DIR/tmp/generated-stage-llvm-entry."* ]] && rm -rf "$NESTED_CLASSIFIER_TMP"
    [[ -n "$NESTED_TMP" && "$NESTED_TMP" == "$ROOT_DIR/tmp/generated-stage-pre-function-memory."* ]] && rm -rf "$NESTED_TMP"
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

TAIL_LINES="${TAIL_LINES:-80}"
STAGE2_BUILD_TIMEOUT="${STAGE2_BUILD_TIMEOUT:-600}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-120}"
SMOKE_MEM_MB="${SMOKE_MEM_MB:-4096}"
HIGH_NON_GC_BYTES="${HIGH_NON_GC_BYTES:-1000000000}"
DEFAULT_SUMMARY="$TMP_DIR/default_memory.summary"
STAGE1_SUMMARY="$TMP_DIR/stage1_memory.summary"

echo "# Generated Stage Pre-HIR Memory Split Classifier"
echo "repo=$ROOT_DIR"
echo "tail_lines=$TAIL_LINES"
echo "stage2_build_timeout=$STAGE2_BUILD_TIMEOUT"
echo "smoke_timeout=$SMOKE_TIMEOUT"
echo "smoke_mem_mb=$SMOKE_MEM_MB"
echo "high_non_gc_bytes=$HIGH_NON_GC_BYTES"
echo "require_split=${REQUIRE_SPLIT:-0}"

set +e
KEEP_TMP=1 \
TAIL_LINES="$TAIL_LINES" \
STAGE2_BUILD_TIMEOUT="$STAGE2_BUILD_TIMEOUT" \
SMOKE_TIMEOUT="$SMOKE_TIMEOUT" \
SMOKE_MEM_MB="$SMOKE_MEM_MB" \
HIGH_NON_GC_BYTES="$HIGH_NON_GC_BYTES" \
REQUIRE_OWNER=0 \
  "$ROOT_DIR/scripts/generated_stage_pre_function_memory_owner_classifier.sh" "$@" >"$OWNER_LOG" 2>&1
owner_rc=$?
set -e

owner_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, index($0, "=") + 1); found = 1; exit } END { if (!found) exit 1 }' "$OWNER_LOG" 2>/dev/null || true
}

NESTED_TMP="$(owner_value kept_tmp)"
NESTED_REPORT_TMP="$(owner_value kept_report_tmp)"
NESTED_CLASSIFIER_TMP="$(owner_value kept_classifier_tmp)"
RUNTIME_LEDGER="$(owner_value runtime_ledger)"
STAGE1_LEDGER="$(owner_value stage1_ledger)"
STAGE1_CONTROL_LOG="$(owner_value stage1_control_log)"

memory_summary() {
  local ledger="$1"
  local mode="$2"
  awk -F'\t' -v mode="$mode" -v high="$HIGH_NON_GC_BYTES" '
    function field(name,   i,n,j,parts,value) {
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

classify_pre_hir_phase() {
  local phase="$1"
  case "$phase" in
    cli.compile_entry)
      echo "pre_hir_pressure_compile_entry"
      ;;
    cli.parse_start)
      echo "pre_hir_pressure_parse_entry"
      ;;
    cli.parse_prelude_done)
      echo "pre_hir_pressure_prelude_parse"
      ;;
    cli.parse_user_done|cli.parse_done)
      echo "pre_hir_pressure_user_parse_or_source_retention"
      ;;
    cli.semantic_compile_done|cli.semantic_shadow_done|cli.link_libraries_done)
      echo "pre_hir_pressure_semantic_prepass"
      ;;
    cli.hir_entry|cli.hir_maps_ready|cli.hir_module_ready|cli.hir_converter_bound)
      echo "pre_hir_pressure_hir_setup"
      ;;
    cli.hir_collect_done)
      echo "pre_hir_pressure_hir_collect"
      ;;
    cli.hir_register_types_done)
      echo "pre_hir_pressure_hir_type_registration"
      ;;
    cli.hir_register_functions_done)
      echo "pre_hir_pressure_hir_function_registration"
      ;;
    cli.hir_fixup_ivars_done)
      echo "pre_hir_pressure_hir_layout_fixup"
      ;;
    cli.hir_lower_main_done)
      echo "pre_hir_pressure_lower_main"
      ;;
    cli.hir_flush_pending_done|cli.hir_final)
      echo "pre_hir_pressure_pending_flush_or_final"
      ;;
    "")
      echo "pre_hir_pressure_low_until_hir_final"
      ;;
    *)
      echo "pre_hir_memory_drift"
      ;;
  esac
}

if [[ -f "$RUNTIME_LEDGER" ]]; then
  memory_summary "$RUNTIME_LEDGER" "default_workers" >"$DEFAULT_SUMMARY"
else
  : >"$DEFAULT_SUMMARY"
fi

if [[ -f "$STAGE1_LEDGER" ]]; then
  memory_summary "$STAGE1_LEDGER" "stage1_workers1" >"$STAGE1_SUMMARY"
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
default_max_owner="$(get_summary_value max_owner "$DEFAULT_SUMMARY")"
default_max_non_gc="$(get_summary_value max_non_gc "$DEFAULT_SUMMARY")"
default_last_phase="$(get_summary_value last_phase "$DEFAULT_SUMMARY")"
default_last_non_gc="$(get_summary_value last_non_gc "$DEFAULT_SUMMARY")"

stage1_rows="$(get_summary_value rows "$STAGE1_SUMMARY")"
stage1_first_high_phase="$(get_summary_value first_high_phase "$STAGE1_SUMMARY")"
stage1_max_phase="$(get_summary_value max_phase "$STAGE1_SUMMARY")"
stage1_max_non_gc="$(get_summary_value max_non_gc "$STAGE1_SUMMARY")"
stage1_last_phase="$(get_summary_value last_phase "$STAGE1_SUMMARY")"
stage1_last_non_gc="$(get_summary_value last_non_gc "$STAGE1_SUMMARY")"

stage1_control_rc="$(owner_value stage1_control_rc)"
stage1_control_run_rc="$(owner_value stage1_control_run_rc)"

classification="pre_hir_memory_drift"
if [[ "${default_rows:-0}" == "0" ]]; then
  classification="pre_hir_memory_phase_missing"
elif [[ "${stage1_control_rc:-99}" -ne 0 || "${stage1_control_run_rc:-99}" -ne 0 || "${stage1_rows:-0}" == "0" ]]; then
  classification="pre_hir_stage1_control_failed"
elif [[ "${stage1_max_non_gc:-0}" -ge "$HIGH_NON_GC_BYTES" ]]; then
  classification="pre_hir_memory_drift"
else
  classification="$(classify_pre_hir_phase "${default_first_high_phase:-}")"
fi

terminal_status="terminal"
case "$classification" in
  pre_hir_memory_phase_missing|pre_hir_stage1_control_failed|pre_hir_memory_drift)
    terminal_status="non_terminal"
    ;;
esac

echo "owner_rc=$owner_rc"
echo "owner.classification=$(owner_value classification)"
echo "owner.default_first_high_phase=$(owner_value default_first_high_phase)"
echo "owner.default_first_high_owner=$(owner_value default_first_high_owner)"
echo "owner.default_first_high_non_gc=$(owner_value default_first_high_non_gc)"
echo "default_memory_rows=${default_rows:-0}"
echo "default_first_phase=${default_first_phase:-}"
echo "default_first_non_gc=${default_first_non_gc:-0}"
echo "default_first_high_phase=${default_first_high_phase:-}"
echo "default_first_high_owner=${default_first_high_owner:-}"
echo "default_first_high_non_gc=${default_first_high_non_gc:-0}"
echo "default_max_phase=${default_max_phase:-}"
echo "default_max_owner=${default_max_owner:-}"
echo "default_max_non_gc=${default_max_non_gc:-0}"
echo "default_last_phase=${default_last_phase:-}"
echo "default_last_non_gc=${default_last_non_gc:-0}"
echo "stage1_control_rc=${stage1_control_rc:-99}"
echo "stage1_control_run_rc=${stage1_control_run_rc:-99}"
echo "stage1_control_stdout=$(owner_value stage1_control_stdout)"
echo "stage1_memory_rows=${stage1_rows:-0}"
echo "stage1_first_high_phase=${stage1_first_high_phase:-}"
echo "stage1_max_phase=${stage1_max_phase:-}"
echo "stage1_max_non_gc=${stage1_max_non_gc:-0}"
echo "stage1_last_phase=${stage1_last_phase:-}"
echo "stage1_last_non_gc=${stage1_last_non_gc:-0}"
echo "classification=$classification"
echo "terminal_status=$terminal_status"
echo "next_allowed_outcome=owner_edge_receipt_or_lane_refutation_or_board_pivot_or_impasse"
echo "owner_log=$OWNER_LOG"
echo "runtime_ledger=$RUNTIME_LEDGER"
echo "stage1_ledger=$STAGE1_LEDGER"
echo "stage1_control_log=$STAGE1_CONTROL_LOG"

if [[ "$terminal_status" != "terminal" || "${TAIL_ALWAYS:-0}" == "1" ]]; then
  echo "owner_tail:"
  tail -120 "$OWNER_LOG" || true
  if [[ -f "$STAGE1_CONTROL_LOG" ]]; then
    echo "stage1_control_tail:"
    tail -80 "$STAGE1_CONTROL_LOG" || true
  fi
fi

if [[ "${REQUIRE_SPLIT:-0}" == "1" && "$terminal_status" != "terminal" ]]; then
  exit 9
fi
