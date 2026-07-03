#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_function_emission_attempt_classifier.sh [source.cr]

Build/use a generated s2 compiler and stop immediately before the active
function-emission attempt selected by the L15 outcome ledger. The classifier
distinguishes whether resource pressure is already high before the active
function starts, or whether the active function remains the next owner edge.

Environment:
  KEEP_TMP=1
  STAGE1_COMPILER
  GENERATED_S2
  STAGE1_MODE=debug
  STAGE2_BUILD_TIMEOUT=600
  STAGE2_BUILD_MEM_MB=4096
  SMOKE_TIMEOUT=120
  SMOKE_MEM_MB=4096
  HIGH_RSS_MB=3072
  STOP_INDEX=87
  EXPECT_FUNCTION=__vdispatch__IO::FileDescriptor#system_write$Slice(UInt8)$T122
  REQUIRE_CLASSIFICATION=1

Classifications:
  select_active_function_attempt_edge
  select_pre_attempt_retained_state_edge
  function_attempt_stop_gate_failed
  function_attempt_classifier_build_failed

This is a discriminator only. A clean stop-before result is not a fix and does
not license a per-method patch without the next owner-edge receipt.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x /usr/bin/time ]]; then
  echo "classification=function_attempt_classifier_missing_time_l"
  echo "reason=/usr/bin/time_missing"
  exit 9
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-function-attempt.XXXXXX")"

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
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

STAGE1_MODE="${STAGE1_MODE:-debug}"
STAGE2_BUILD_TIMEOUT="${STAGE2_BUILD_TIMEOUT:-600}"
STAGE2_BUILD_MEM_MB="${STAGE2_BUILD_MEM_MB:-4096}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-120}"
SMOKE_MEM_MB="${SMOKE_MEM_MB:-4096}"
HIGH_RSS_MB="${HIGH_RSS_MB:-3072}"
STOP_INDEX="${STOP_INDEX:-87}"
EXPECT_FUNCTION="${EXPECT_FUNCTION:-__vdispatch__IO::FileDescriptor#system_write\$Slice(UInt8)\$T122}"

STAGE1="${STAGE1_COMPILER:-$TMP_DIR/adamas_stage1}"
S2="${GENERATED_S2:-$TMP_DIR/adamas_s2}"
STAGE1_LOG="$TMP_DIR/stage1_build.log"
S2_BUILD_LOG="$TMP_DIR/s2_build.log"
LEDGER="$TMP_DIR/runtime_ledger.tsv"
: >"$LEDGER"

echo "# Generated Stage Function Emission Attempt Classifier"
echo "repo=$ROOT_DIR"
echo "source=$SOURCE"
echo "stage1=$STAGE1"
echo "generated_s2=$S2"
echo "stop_index=$STOP_INDEX"
echo "expect_function=$EXPECT_FUNCTION"
echo "high_rss_mb=$HIGH_RSS_MB"
echo "smoke_timeout=$SMOKE_TIMEOUT"
echo "smoke_mem_mb=$SMOKE_MEM_MB"
echo "require_classification=${REQUIRE_CLASSIFICATION:-0}"

if [[ -z "${STAGE1_COMPILER:-}" ]]; then
  set +e
  "$ROOT_DIR/scripts/build_stage1_original_cached.sh" "$STAGE1_MODE" "$STAGE1" --error-trace >"$STAGE1_LOG" 2>&1
  stage1_rc=$?
  set -e
  echo "stage1_build_rc=$stage1_rc"
  if [[ $stage1_rc -ne 0 || ! -x "$STAGE1" ]]; then
    echo "classification=function_attempt_classifier_build_failed"
    echo "stage1_build_tail:"
    tail -80 "$STAGE1_LOG" || true
    exit 9
  fi
else
  echo "stage1_build_rc=skipped"
  if [[ ! -x "$STAGE1" ]]; then
    echo "provided_stage1_not_executable=$STAGE1"
    echo "classification=function_attempt_classifier_build_failed"
    exit 9
  fi
fi

if [[ -z "${GENERATED_S2:-}" ]]; then
  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$STAGE1" "$STAGE2_BUILD_TIMEOUT" "$STAGE2_BUILD_MEM_MB" \
    "$ROOT_DIR/src/adamas.cr" -o "$S2" >"$S2_BUILD_LOG" 2>&1
  s2_build_rc=$?
  set -e
  echo "s2_build_rc=$s2_build_rc"
  if [[ $s2_build_rc -ne 0 || ! -x "$S2" ]]; then
    echo "classification=function_attempt_classifier_build_failed"
    echo "s2_build_tail:"
    tail -100 "$S2_BUILD_LOG" || true
    exit 9
  fi
else
  echo "s2_build_rc=skipped"
  if [[ ! -x "$S2" ]]; then
    echo "provided_generated_s2_not_executable=$S2"
    echo "classification=function_attempt_classifier_build_failed"
    exit 9
  fi
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

ledger_field_for_mode() {
  local mode="$1"
  local row="$2"
  local key="$3"
  awk -F'\t' -v tx="gsetx_function_attempt" -v mode="$mode" -v row="$row" -v key="$key" '
    $1 == "GSETX" && $2 == tx && $3 == mode && $4 == row {
      for (i = 5; i <= NF; i++) {
        n = split($i, parts, " ")
        for (j = 1; j <= n; j++) {
          if (index(parts[j], key "=") == 1) {
            print substr(parts[j], length(key) + 2)
            found = 1
          }
        }
      }
    }
    END {
      if (!found) exit 1
    }
  ' "$LEDGER" 2>/dev/null | tail -1 || true
}

ledger_count_for_mode() {
  local mode="$1"
  local row="$2"
  awk -F'\t' -v tx="gsetx_function_attempt" -v mode="$mode" -v row="$row" '
    $1 == "GSETX" && $2 == tx && $3 == mode && $4 == row { count++ }
    END { print count + 0 }
  ' "$LEDGER" 2>/dev/null || echo 0
}

run_stop_probe() {
  local mode="$1"
  local out_bin="$TMP_DIR/${mode}_out"
  local log="$TMP_DIR/${mode}_stop_before.log"

  set +e
  if [[ "$mode" == "workers1" ]]; then
    env ADAMAS_STOP_BEFORE_LLVM_FUNCTION_INDEX="$STOP_INDEX" \
      ADAMAS_GSETX_FUNCTION_EMISSION_OUTCOMES=1 \
      ADAMAS_GSETX_MEMORY_PHASES=1 \
      ADAMAS_GSETX_ID=gsetx_function_attempt \
      ADAMAS_GSETX_LEDGER="$LEDGER" \
      ADAMAS_GSETX_RUN_MODE="$mode" \
      ADAMAS_LLVM_WORKERS=1 \
      /usr/bin/time -l "$ROOT_DIR/scripts/run_safe.sh" "$S2" "$SMOKE_TIMEOUT" "$SMOKE_MEM_MB" \
        "$SOURCE" -o "$out_bin" >"$log" 2>&1
  else
    env ADAMAS_STOP_BEFORE_LLVM_FUNCTION_INDEX="$STOP_INDEX" \
      ADAMAS_GSETX_FUNCTION_EMISSION_OUTCOMES=1 \
      ADAMAS_GSETX_MEMORY_PHASES=1 \
      ADAMAS_GSETX_ID=gsetx_function_attempt \
      ADAMAS_GSETX_LEDGER="$LEDGER" \
      ADAMAS_GSETX_RUN_MODE="$mode" \
      /usr/bin/time -l "$ROOT_DIR/scripts/run_safe.sh" "$S2" "$SMOKE_TIMEOUT" "$SMOKE_MEM_MB" \
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

  local outcome_rows
  outcome_rows="$(ledger_count_for_mode "$mode" "llvm.function_emission_outcome")"
  local phase_rows
  phase_rows="$(ledger_count_for_mode "$mode" "llvm.function_emission_phase")"
  local memory_rows
  memory_rows="$(ledger_count_for_mode "$mode" "memory.phase")"
  local status
  status="$(ledger_field_for_mode "$mode" "llvm.function_emission_outcome" "status")"
  local index
  index="$(ledger_field_for_mode "$mode" "llvm.function_emission_outcome" "index")"
  local function
  function="$(ledger_field_for_mode "$mode" "llvm.function_emission_outcome" "function")"

  echo "${mode}_rc=$rc"
  echo "${mode}_run_safe_exit=${exit_code:-missing}"
  echo "${mode}_peak_rss_bytes=${peak_bytes:-0}"
  echo "${mode}_peak_rss_mb=$peak_mb"
  echo "${mode}_memory_kill=$memory_kill"
  echo "${mode}_memory_kill_kb=${kill_kb:-0}"
  echo "${mode}_outcome_rows=$outcome_rows"
  echo "${mode}_phase_rows=$phase_rows"
  echo "${mode}_memory_phase_rows=$memory_rows"
  echo "${mode}_last_outcome_status=${status:-missing}"
  echo "${mode}_last_outcome_index=${index:-missing}"
  echo "${mode}_last_outcome_function=${function:-missing}"
  echo "${mode}_log=$log"
}

SUMMARY="$TMP_DIR/stop_summary.out"
{
  run_stop_probe "default_workers"
  run_stop_probe "workers1"
} >"$SUMMARY"

cat "$SUMMARY"

read_metric() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { print substr($0, index($0, "=") + 1); exit }' "$SUMMARY"
}

default_peak="$(read_metric default_workers_peak_rss_mb)"
workers1_peak="$(read_metric workers1_peak_rss_mb)"
default_kill="$(read_metric default_workers_memory_kill)"
workers1_kill="$(read_metric workers1_memory_kill)"
default_rc="$(read_metric default_workers_rc)"
workers1_rc="$(read_metric workers1_rc)"
default_exit="$(read_metric default_workers_run_safe_exit)"
workers1_exit="$(read_metric workers1_run_safe_exit)"
default_status="$(read_metric default_workers_last_outcome_status)"
workers1_status="$(read_metric workers1_last_outcome_status)"
default_index="$(read_metric default_workers_last_outcome_index)"
workers1_index="$(read_metric workers1_last_outcome_index)"
default_function="$(read_metric default_workers_last_outcome_function)"
workers1_function="$(read_metric workers1_last_outcome_function)"

classification="function_attempt_stop_gate_failed"
if [[ "$default_status" == "stop_before" &&
      "$workers1_status" == "stop_before" &&
      "$default_index" == "$STOP_INDEX" &&
      "$workers1_index" == "$STOP_INDEX" &&
      "$default_function" == "$EXPECT_FUNCTION" &&
      "$workers1_function" == "$EXPECT_FUNCTION" ]]; then
  if [[ "$default_kill" == "1" || "$workers1_kill" == "1" ||
        "${default_peak:-999999}" -ge "$HIGH_RSS_MB" ||
        "${workers1_peak:-999999}" -ge "$HIGH_RSS_MB" ]]; then
    classification="select_pre_attempt_retained_state_edge"
  elif [[ "$default_rc" == "0" && "$workers1_rc" == "0" &&
          "$default_exit" == "0" && "$workers1_exit" == "0" ]]; then
    classification="select_active_function_attempt_edge"
  fi
fi

echo "classification=$classification"
echo "ledger=$LEDGER"

if [[ "${REQUIRE_CLASSIFICATION:-0}" == "1" ]]; then
  case "$classification" in
    select_active_function_attempt_edge|select_pre_attempt_retained_state_edge)
      ;;
    *)
      exit 9
      ;;
  esac
fi
