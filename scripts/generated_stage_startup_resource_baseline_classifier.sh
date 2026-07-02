#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_startup_resource_baseline_classifier.sh [source.cr]

Build/use a fresh generated s2 compiler, then classify the default-worker
resource boundary with OS RSS evidence at explicit compile-entry, parse, HIR,
and MIR stop gates.

This is the post-0k-DR startup/process-baseline falsifier. It does not use
GC non_gc as the owner signal: 0k-DR already showed that metric is high at
compile entry. This script asks whether actual process RSS is already high at
startup, or whether the resource boundary still moves later in the pipeline.

Environment:
  KEEP_TMP=1                 Keep temp dirs for manual inspection.
  REQUIRE_CLASSIFICATION=1   Exit nonzero unless a terminal classification is
                             produced.
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
  startup_compile_entry_resource
  parse_resource_boundary
  hir_resource_boundary
  mir_resource_boundary
  llvm_or_later_resource_boundary
  resource_gate_clean
  startup_resource_classifier_missing_time_l
  startup_resource_classifier_build_failed
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x /usr/bin/time ]]; then
  echo "classification=startup_resource_classifier_missing_time_l"
  echo "reason=/usr/bin/time_missing"
  exit 9
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-startup-resource.XXXXXX")"
NESTED_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
    [[ -n "$NESTED_TMP" ]] && echo "kept_classifier_tmp=$NESTED_TMP"
  else
    [[ -n "$NESTED_TMP" && "$NESTED_TMP" == "$ROOT_DIR/tmp/generated-stage-llvm-entry."* ]] && rm -rf "$NESTED_TMP"
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
CLASSIFIER_OUT="$TMP_DIR/generated_stage_llvm_entry.out"

echo "# Generated Stage Startup Resource Baseline Classifier"
echo "repo=$ROOT_DIR"
echo "source=$SOURCE"
echo "high_rss_mb=$HIGH_RSS_MB"
echo "smoke_timeout=$SMOKE_TIMEOUT"
echo "smoke_mem_mb=$SMOKE_MEM_MB"
echo "require_classification=${REQUIRE_CLASSIFICATION:-0}"

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
classifier_rc=$?
set -e

value_of() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, index($0, "=") + 1); found = 1; exit } END { if (!found) exit 1 }' "$CLASSIFIER_OUT" 2>/dev/null || true
}

NESTED_TMP="$(value_of kept_tmp)"
STAGE1_PATH="$(value_of stage1)"
S2_PATH="$(value_of generated_s2)"

if [[ "$classifier_rc" -ne 0 || ! -x "$S2_PATH" ]]; then
  echo "classifier_rc=$classifier_rc"
  echo "nested.classification=$(value_of classification)"
  echo "classification=startup_resource_classifier_build_failed"
  echo "classifier_tail:"
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
  local env_key="$3"
  local extra_env_key="${4:-}"
  local extra_env_value="${5:-}"
  local out_bin="$TMP_DIR/${label}.out"
  local log="$TMP_DIR/${label}.log"

  set +e
  if [[ -n "$extra_env_key" ]]; then
    env "$env_key=1" "$extra_env_key=$extra_env_value" \
      /usr/bin/time -l "$ROOT_DIR/scripts/run_safe.sh" "$compiler" "$SMOKE_TIMEOUT" "$SMOKE_MEM_MB" \
        "$SOURCE" -o "$out_bin" >"$log" 2>&1
  else
    env "$env_key=1" \
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

SUMMARY="$TMP_DIR/probe_summary.out"
{
  run_stop_probe "stage1_compile_entry_summary" "$STAGE1_PATH" "ADAMAS_STOP_AFTER_COMPILE_ENTRY"
  run_stop_probe "s2_compile_entry_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_COMPILE_ENTRY"
  run_stop_probe "s2_parse_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_PARSE"
  run_stop_probe "s2_hir_summary" "$S2_PATH" "ADAMAS_STOP_AFTER_HIR"
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

emit_prefixed_summary "stage1_compile_entry" "stage1_compile_entry_summary"
emit_prefixed_summary "s2_compile_entry" "s2_compile_entry_summary"
emit_prefixed_summary "s2_parse" "s2_parse_summary"
emit_prefixed_summary "s2_hir" "s2_hir_summary"
emit_prefixed_summary "s2_mir" "s2_mir_summary"

s2_compile_entry_rc="$(read_metric s2_compile_entry_summary_rc "$SUMMARY")"
s2_compile_entry_peak="$(read_metric s2_compile_entry_summary_peak_rss_mb "$SUMMARY")"
s2_compile_entry_kill="$(read_metric s2_compile_entry_summary_memory_kill "$SUMMARY")"
s2_parse_rc="$(read_metric s2_parse_summary_rc "$SUMMARY")"
s2_parse_peak="$(read_metric s2_parse_summary_peak_rss_mb "$SUMMARY")"
s2_parse_kill="$(read_metric s2_parse_summary_memory_kill "$SUMMARY")"
s2_hir_rc="$(read_metric s2_hir_summary_rc "$SUMMARY")"
s2_hir_peak="$(read_metric s2_hir_summary_peak_rss_mb "$SUMMARY")"
s2_hir_kill="$(read_metric s2_hir_summary_memory_kill "$SUMMARY")"
s2_mir_rc="$(read_metric s2_mir_summary_rc "$SUMMARY")"
s2_mir_peak="$(read_metric s2_mir_summary_peak_rss_mb "$SUMMARY")"
s2_mir_kill="$(read_metric s2_mir_summary_memory_kill "$SUMMARY")"

nested_default_memory_kill="$(value_of default_workers_memory_kill)"
nested_workers1_memory_kill="$(value_of workers1_memory_kill)"
nested_default_after_lower_main="$(value_of default_workers_after_lower_main)"
nested_workers1_after_lower_main="$(value_of workers1_after_lower_main)"
nested_classification="$(value_of classification)"

classification="resource_gate_clean"
if [[ "${s2_compile_entry_rc:-99}" -ne 0 || "${s2_compile_entry_kill:-1}" == "1" || "${s2_compile_entry_peak:-999999}" -ge "$HIGH_RSS_MB" ]]; then
  classification="startup_compile_entry_resource"
elif [[ "${s2_parse_rc:-99}" -ne 0 || "${s2_parse_kill:-1}" == "1" || "${s2_parse_peak:-999999}" -ge "$HIGH_RSS_MB" ]]; then
  classification="parse_resource_boundary"
elif [[ "${s2_hir_rc:-99}" -ne 0 || "${s2_hir_kill:-1}" == "1" || "${s2_hir_peak:-999999}" -ge "$HIGH_RSS_MB" ]]; then
  classification="hir_resource_boundary"
elif [[ "${s2_mir_rc:-99}" -ne 0 || "${s2_mir_kill:-1}" == "1" || "${s2_mir_peak:-999999}" -ge "$HIGH_RSS_MB" ]]; then
  classification="mir_resource_boundary"
elif [[ "${nested_default_memory_kill:-0}" == "1" || "${nested_workers1_memory_kill:-0}" == "1" ]]; then
  classification="llvm_or_later_resource_boundary"
fi

echo "nested.classification=$nested_classification"
echo "nested.default_workers_after_lower_main=$nested_default_after_lower_main"
echo "nested.default_workers_memory_kill=$nested_default_memory_kill"
echo "nested.workers1_after_lower_main=$nested_workers1_after_lower_main"
echo "nested.workers1_memory_kill=$nested_workers1_memory_kill"
echo "classification=$classification"
echo "classifier_log=$CLASSIFIER_OUT"

if [[ "${REQUIRE_CLASSIFICATION:-0}" == "1" ]]; then
  case "$classification" in
    startup_compile_entry_resource|parse_resource_boundary|hir_resource_boundary|mir_resource_boundary|llvm_or_later_resource_boundary|resource_gate_clean)
      ;;
    *)
      exit 9
      ;;
  esac
fi
