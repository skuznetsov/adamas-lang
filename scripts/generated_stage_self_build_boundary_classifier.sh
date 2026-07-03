#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_self_build_boundary_classifier.sh

Classify the generated-s2 self-build boundary by running a stage1 compiler on
src/adamas.cr with existing compile-entry, parse, HIR, and MIR stop gates. This
is the L16 falsifier for cases where generated_stage_mode_resource_lane cannot
produce a generated s2 compiler at all.

Environment:
  KEEP_TMP=1                 Keep temp dir for manual inspection.
  REQUIRE_CLASSIFICATION=1   Exit nonzero unless a terminal classification is
                             produced.
  HIGH_RSS_MB                Peak RSS threshold for "high" (default: 3072).
  STAGE1_COMPILER            Stage1 compiler to test. If empty, build one into
                             the temp dir.
  STAGE1_MODE                Build mode label only (default: debug).
  STOP_TIMEOUT               run_safe timeout for stop gates (default: 300).
  STOP_MEM_MB                run_safe RSS cap for stop gates (default: 4096).
  TAIL_LINES                 Log tail lines for failing gates (default: 30).

Classifications:
  self_build_compile_entry_resource
  self_build_parse_resource
  self_build_hir_boundary
  self_build_mir_boundary
  self_build_after_mir_boundary
  self_build_gate_clean
  self_build_classifier_stage1_build_failed
  self_build_classifier_missing_time_l
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x /usr/bin/time ]]; then
  echo "classification=self_build_classifier_missing_time_l"
  echo "reason=/usr/bin/time_missing"
  exit 9
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-self-build.XXXXXX")"

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

HIGH_RSS_MB="${HIGH_RSS_MB:-3072}"
STOP_TIMEOUT="${STOP_TIMEOUT:-300}"
STOP_MEM_MB="${STOP_MEM_MB:-4096}"
TAIL_LINES="${TAIL_LINES:-30}"
STAGE1_MODE="${STAGE1_MODE:-debug}"
STAGE1_PATH="${STAGE1_COMPILER:-}"
SOURCE="$ROOT_DIR/src/adamas.cr"

echo "# Generated Stage Self-Build Boundary Classifier"
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
    echo "classification=self_build_classifier_stage1_build_failed"
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
  env "$env_key=1" \
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

SUMMARY="$TMP_DIR/probe_summary.out"
{
  run_stop_probe "compile_entry" "ADAMAS_STOP_AFTER_COMPILE_ENTRY"
  run_stop_probe "parse" "ADAMAS_STOP_AFTER_PARSE"
  run_stop_probe "hir" "ADAMAS_STOP_AFTER_HIR"
  run_stop_probe "mir" "ADAMAS_STOP_AFTER_MIR"
} >"$SUMMARY"

cat "$SUMMARY"

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

classification="self_build_gate_clean"
if gate_bad "compile_entry"; then
  classification="self_build_compile_entry_resource"
elif gate_bad "parse"; then
  classification="self_build_parse_resource"
elif gate_bad "hir"; then
  classification="self_build_hir_boundary"
elif gate_bad "mir"; then
  classification="self_build_mir_boundary"
else
  classification="self_build_after_mir_boundary"
fi

echo "classification=$classification"

if [[ "${REQUIRE_CLASSIFICATION:-0}" == "1" ]]; then
  case "$classification" in
    self_build_compile_entry_resource|self_build_parse_resource|self_build_hir_boundary|self_build_mir_boundary|self_build_after_mir_boundary|self_build_gate_clean)
      ;;
    *)
      exit 9
      ;;
  esac
fi
