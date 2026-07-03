#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_self_build_hir_boundary_classifier.sh

Refine the B5 generated-s2 self-build HIR boundary. This assumes the coarser
generated_stage_self_build_boundary_classifier has already selected
self_build_hir_boundary and splits the interval between lower_main returning
and the existing ADAMAS_STOP_AFTER_HIR gate.

Environment:
  KEEP_TMP=1                 Keep temp dir for manual inspection.
  REQUIRE_CLASSIFICATION=1   Exit nonzero unless a terminal classification is
                             produced.
  HIGH_RSS_MB                Peak RSS threshold for "high" (default: 12288).
  STAGE1_COMPILER            Compiler to test. If empty, build one into tmp.
  STAGE1_MODE                Build mode label only (default: debug).
  STOP_TIMEOUT               run_safe timeout for stop gates (default: 900).
  STOP_MEM_MB                run_safe RSS cap for stop gates (default: 12288).
  TAIL_LINES                 Log tail lines for failing gates (default: 30).

Classifications:
  self_build_compile_entry_resource
  self_build_parse_resource
  self_build_lower_main_boundary
  self_build_hir_lower_main_bookkeeping_boundary
  self_build_hir_fun_main_scan_boundary
  self_build_hir_fun_main_lower_boundary
  self_build_hir_fun_main_flush_boundary
  self_build_hir_before_flush_pending_boundary
  self_build_hir_flush_pending_boundary
  self_build_hir_refresh_type_params_boundary
  self_build_hir_rta_boundary
  self_build_hir_tail_boundary
  self_build_after_hir_boundary
  self_build_hir_classifier_stage1_build_failed
  self_build_hir_classifier_missing_time_l
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x /usr/bin/time ]]; then
  echo "classification=self_build_hir_classifier_missing_time_l"
  echo "reason=/usr/bin/time_missing"
  exit 9
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-self-build-hir.XXXXXX")"

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

HIGH_RSS_MB="${HIGH_RSS_MB:-12288}"
STOP_TIMEOUT="${STOP_TIMEOUT:-900}"
STOP_MEM_MB="${STOP_MEM_MB:-12288}"
TAIL_LINES="${TAIL_LINES:-30}"
STAGE1_MODE="${STAGE1_MODE:-debug}"
STAGE1_PATH="${STAGE1_COMPILER:-}"
SOURCE="$ROOT_DIR/src/adamas.cr"

echo "# Generated Stage Self-Build HIR Boundary Classifier"
echo "repo=$ROOT_DIR"
echo "source=$SOURCE"
echo "high_rss_mb=$HIGH_RSS_MB"
echo "stop_timeout=$STOP_TIMEOUT"
echo "stop_mem_mb=$STOP_MEM_MB"
echo "stage1_mode=$STAGE1_MODE"
echo "require_classification=${REQUIRE_CLASSIFICATION:-0}"

if [[ -z "$STAGE1_PATH" ]]; then
  STAGE1_PATH="$TMP_DIR/adamas_stage1"
  set +e
  crystal build "$ROOT_DIR/src/adamas.cr" -o "$STAGE1_PATH" --error-trace >"$TMP_DIR/stage1_build.log" 2>&1
  stage1_build_rc=$?
  set -e
  echo "stage1_build_rc=$stage1_build_rc"
  echo "stage1=$STAGE1_PATH"
  if [[ "$stage1_build_rc" -ne 0 || ! -x "$STAGE1_PATH" ]]; then
    echo "classification=self_build_hir_classifier_stage1_build_failed"
    echo "stage1_build_log=$TMP_DIR/stage1_build.log"
    echo "stage1_build_tail:"
    tail -"$TAIL_LINES" "$TMP_DIR/stage1_build.log" || true
    exit 9
  fi
else
  echo "stage1_build_rc=skipped"
  echo "stage1=$STAGE1_PATH"
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

run_safe_timeout_kill() {
  local log="$1"
  grep -q '^\[KILL\] Timeout after ' "$log" && echo 1 || echo 0
}

run_stop_probe() {
  local label="$1"
  local env_key="$2"
  local out_bin="$TMP_DIR/${label}.out"
  local log="$TMP_DIR/${label}.log"

  set +e
  env "$env_key=1" ADAMAS_CODEPATH_STATUS_LEDGER=1 \
    /usr/bin/time -l "$ROOT_DIR/scripts/run_safe.sh" "$STAGE1_PATH" "$STOP_TIMEOUT" "$STOP_MEM_MB" \
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
  local memory_kill_kb
  memory_kill_kb="$(run_safe_memory_kill_kb "$log")"
  local memory_kill=0
  [[ -n "$memory_kill_kb" ]] && memory_kill=1
  local timeout_kill
  timeout_kill="$(run_safe_timeout_kill "$log")"

  echo "${label}_rc=$rc"
  echo "${label}_run_safe_exit=${exit_code:-missing}"
  echo "${label}_peak_rss_bytes=${peak_bytes:-0}"
  echo "${label}_peak_rss_mb=$peak_mb"
  echo "${label}_memory_kill=$memory_kill"
  echo "${label}_memory_kill_kb=${memory_kill_kb:-0}"
  echo "${label}_timeout_kill=$timeout_kill"
  echo "${label}_log=$log"

  if [[ "$rc" -ne 0 || "$memory_kill" == "1" || "$timeout_kill" == "1" || "$peak_mb" -ge "$HIGH_RSS_MB" ]]; then
    echo "${label}_tail:"
    tail -"$TAIL_LINES" "$log" || true
  fi
}

codepath_status_for() {
  local log="$1"
  local path="$2"
  sed -nE "s/.*\\[CODEPATH_STATUS\\].* path=${path} status=([^ ]+).*/\\1/p" "$log" | tail -1
}

SUMMARY="$TMP_DIR/probe_summary.out"
: >"$SUMMARY"

read_metric() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print $2; exit }' "$SUMMARY"
}

gate_bad() {
  local label="$1"
  local rc peak memory_kill timeout_kill
  rc="$(read_metric "${label}_rc")"
  peak="$(read_metric "${label}_peak_rss_mb")"
  memory_kill="$(read_metric "${label}_memory_kill")"
  timeout_kill="$(read_metric "${label}_timeout_kill")"

  [[ "${rc:-99}" -ne 0 || "${memory_kill:-1}" == "1" || "${timeout_kill:-1}" == "1" || "${peak:-999999}" -ge "$HIGH_RSS_MB" ]]
}

run_probe_until_bad() {
  local label="$1"
  local env_key="$2"

  run_stop_probe "$label" "$env_key" | tee -a "$SUMMARY"
  ! gate_bad "$label"
}

fun_main_status="unknown"

if run_probe_until_bad "compile_entry" "ADAMAS_STOP_AFTER_COMPILE_ENTRY" &&
  run_probe_until_bad "parse" "ADAMAS_STOP_AFTER_PARSE" &&
  run_probe_until_bad "lower_main" "ADAMAS_STOP_AFTER_LOWER_MAIN" &&
  run_probe_until_bad "hir_lower_main_done" "ADAMAS_STOP_AFTER_HIR_LOWER_MAIN_DONE" &&
  run_probe_until_bad "hir_fun_main_scan" "ADAMAS_STOP_AFTER_HIR_FUN_MAIN_SCAN"; then
  scan_log="$(read_metric "hir_fun_main_scan_log")"
  fun_main_status="$(codepath_status_for "$scan_log" "fun_main_entry")"
  echo "hir_fun_main_entry_status=${fun_main_status:-missing}" | tee -a "$SUMMARY"

  if [[ "$fun_main_status" == "taken" ]]; then
    run_probe_until_bad "hir_fun_main_lower" "ADAMAS_STOP_AFTER_HIR_FUN_MAIN_LOWER" &&
      run_probe_until_bad "hir_fun_main_flush" "ADAMAS_STOP_AFTER_HIR_FUN_MAIN_FLUSH" || true
  else
    echo "hir_fun_main_lower_skipped=1" | tee -a "$SUMMARY"
    echo "hir_fun_main_lower_rc=0" | tee -a "$SUMMARY"
    echo "hir_fun_main_lower_peak_rss_mb=0" | tee -a "$SUMMARY"
    echo "hir_fun_main_lower_memory_kill=0" | tee -a "$SUMMARY"
    echo "hir_fun_main_lower_timeout_kill=0" | tee -a "$SUMMARY"
    echo "hir_fun_main_flush_skipped=1" | tee -a "$SUMMARY"
    echo "hir_fun_main_flush_rc=0" | tee -a "$SUMMARY"
    echo "hir_fun_main_flush_peak_rss_mb=0" | tee -a "$SUMMARY"
    echo "hir_fun_main_flush_memory_kill=0" | tee -a "$SUMMARY"
    echo "hir_fun_main_flush_timeout_kill=0" | tee -a "$SUMMARY"
  fi

  if ! gate_bad "hir_fun_main_lower" && ! gate_bad "hir_fun_main_flush"; then
    run_probe_until_bad "hir_before_flush_pending" "ADAMAS_STOP_BEFORE_HIR_FLUSH_PENDING" &&
      run_probe_until_bad "hir_flush_pending" "ADAMAS_STOP_AFTER_HIR_FLUSH_PENDING" &&
      run_probe_until_bad "hir_refresh_type_params" "ADAMAS_STOP_AFTER_HIR_REFRESH_TYPE_PARAMS" &&
      run_probe_until_bad "hir_rta" "ADAMAS_STOP_AFTER_HIR_RTA" &&
      run_probe_until_bad "hir" "ADAMAS_STOP_AFTER_HIR" || true
  fi
fi

classification="self_build_after_hir_boundary"
if gate_bad "compile_entry"; then
  classification="self_build_compile_entry_resource"
elif gate_bad "parse"; then
  classification="self_build_parse_resource"
elif gate_bad "lower_main"; then
  classification="self_build_lower_main_boundary"
elif gate_bad "hir_lower_main_done"; then
  classification="self_build_hir_lower_main_bookkeeping_boundary"
elif gate_bad "hir_fun_main_scan"; then
  classification="self_build_hir_fun_main_scan_boundary"
elif gate_bad "hir_fun_main_lower"; then
  classification="self_build_hir_fun_main_lower_boundary"
elif gate_bad "hir_fun_main_flush"; then
  classification="self_build_hir_fun_main_flush_boundary"
elif gate_bad "hir_before_flush_pending"; then
  classification="self_build_hir_before_flush_pending_boundary"
elif gate_bad "hir_flush_pending"; then
  classification="self_build_hir_flush_pending_boundary"
elif gate_bad "hir_refresh_type_params"; then
  classification="self_build_hir_refresh_type_params_boundary"
elif gate_bad "hir_rta"; then
  classification="self_build_hir_rta_boundary"
elif gate_bad "hir"; then
  classification="self_build_hir_tail_boundary"
fi

echo "classification=$classification"

if [[ "${REQUIRE_CLASSIFICATION:-0}" == "1" ]]; then
  case "$classification" in
    self_build_compile_entry_resource|self_build_parse_resource|self_build_lower_main_boundary|self_build_hir_lower_main_bookkeeping_boundary|self_build_hir_fun_main_scan_boundary|self_build_hir_fun_main_lower_boundary|self_build_hir_fun_main_flush_boundary|self_build_hir_before_flush_pending_boundary|self_build_hir_flush_pending_boundary|self_build_hir_refresh_type_params_boundary|self_build_hir_rta_boundary|self_build_hir_tail_boundary|self_build_after_hir_boundary)
      ;;
    *)
      exit 9
      ;;
  esac
fi
