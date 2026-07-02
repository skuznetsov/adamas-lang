#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_llvm_entry_classifier.sh [source.cr]

Build/use a fresh generated s2 compiler, compile a full-prelude tiny source in
two LLVM worker modes, and classify the produced-stage LLVM-entry frontier.

Environment:
  STAGE1_COMPILER            Use an existing stage1 compiler instead of building one.
  GENERATED_S2               Use an existing generated s2 compiler instead of building one.
  KEEP_TMP=1                 Keep the temporary directory and print its path.
  REQUIRE_CLEAN=1            Exit nonzero unless both produced-s2 compile modes succeed.
  REQUIRE_CURRENT_FRONTIER=1 Exit nonzero unless the known 0k-BN frontier reproduces.
  STAGE1_MODE                debug or release for stage1 build (default: debug).
  STAGE2_BUILD_TIMEOUT       run_safe timeout for building generated s2 (default: 300).
  STAGE2_BUILD_MEM_MB        run_safe RSS cap for building generated s2 (default: 4096).
  SMOKE_TIMEOUT              run_safe timeout for produced-s2 compiles (default: 120).
  SMOKE_MEM_MB               run_safe RSS cap for produced-s2 compiles (default: 4096).
  TAIL_LINES                 Failure/frontier tail lines to print per mode (default: 50).

Classifications:
  clean_both_modes                 Both default workers and ADAMAS_LLVM_WORKERS=1 compile.
  current_0k_bn_frontier           Default mode hits the worker/rand+RSS symptom and
                                  workers=1 still exits 139 after lower_main.
  llvm_entry_failure_after_lower_main
                                  At least one mode reaches lower_main then fails.
  worker_only_failure              Default mode fails but workers=1 compiles.
  pre_llvm_entry_failure           Failure occurs before pass3 after lower_main.
  stage1_build_fails
  s2_build_fails

This classifier is behavior-neutral. It must not be used as permission to patch
parallel emission, raise the memory limit as acceptance evidence, force
ADAMAS_LLVM_WORKERS=1, or choose an H7/H8 fix without showing movement here.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-llvm-entry.XXXXXX")"
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
STAGE2_BUILD_TIMEOUT="${STAGE2_BUILD_TIMEOUT:-300}"
STAGE2_BUILD_MEM_MB="${STAGE2_BUILD_MEM_MB:-4096}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-120}"
SMOKE_MEM_MB="${SMOKE_MEM_MB:-4096}"
TAIL_LINES="${TAIL_LINES:-50}"

STAGE1="${STAGE1_COMPILER:-$TMP_DIR/adamas_stage1}"
S2="${GENERATED_S2:-$TMP_DIR/adamas_s2}"
STAGE1_LOG="$TMP_DIR/stage1_build.log"
S2_BUILD_LOG="$TMP_DIR/s2_build.log"
DEFAULT_LOG="$TMP_DIR/default_workers_compile.log"
WORKERS1_LOG="$TMP_DIR/workers1_compile.log"
DEFAULT_OUT="$TMP_DIR/default_workers_out"
WORKERS1_OUT="$TMP_DIR/workers1_out"

print_header() {
  echo "# Generated Stage LLVM Entry Classifier"
  echo "repo=$ROOT_DIR"
  echo "source=$SOURCE"
  echo "stage1=$STAGE1"
  echo "generated_s2=$S2"
  echo "stage1_mode=$STAGE1_MODE"
  echo "stage2_build_timeout=$STAGE2_BUILD_TIMEOUT"
  echo "stage2_build_mem_mb=$STAGE2_BUILD_MEM_MB"
  echo "smoke_timeout=$SMOKE_TIMEOUT"
  echo "smoke_mem_mb=$SMOKE_MEM_MB"
  echo "tail_lines=$TAIL_LINES"
  echo "require_clean=${REQUIRE_CLEAN:-0}"
  echo "require_current_frontier=${REQUIRE_CURRENT_FRONTIER:-0}"
  echo "note: behavior-neutral classifier; no compiler behavior changes"
}

log_has() {
  local pattern="$1"
  local file="$2"
  grep -Fq "$pattern" "$file"
}

emit_mode_summary() {
  local mode="$1"
  local rc="$2"
  local log="$3"
  local output_bin="$4"

  local after_lower_main=0
  local parallel_rand=0
  local parallel_failed=0
  local memory_kill=0
  local exit139=0
  local exit134=0
  local timeout_kill=0
  local binary_present=0

  log_has "pass3 after lower_main call" "$log" && after_lower_main=1
  log_has "parallel emission failed: Invalid bound for rand: 0" "$log" && parallel_rand=1
  log_has "parallel emission failed:" "$log" && parallel_failed=1
  log_has "[KILL] Memory limit:" "$log" && memory_kill=1
  log_has "[CRASH] Segfault (exit 139)" "$log" && exit139=1
  log_has "[CRASH] Abort (exit 134)" "$log" && exit134=1
  log_has "[KILL] Timeout" "$log" && timeout_kill=1
  [[ -x "$output_bin" ]] && binary_present=1

  echo "${mode}_rc=$rc"
  echo "${mode}_after_lower_main=$after_lower_main"
  echo "${mode}_parallel_failed=$parallel_failed"
  echo "${mode}_parallel_rand=$parallel_rand"
  echo "${mode}_memory_kill=$memory_kill"
  echo "${mode}_exit139=$exit139"
  echo "${mode}_exit134=$exit134"
  echo "${mode}_timeout_kill=$timeout_kill"
  echo "${mode}_binary_present=$binary_present"
}

finish_classification() {
  local classification="$1"
  local failure_rc="${2:-9}"

  echo "classification=$classification"
  echo "stage1_build_log=$STAGE1_LOG"
  echo "s2_build_log=$S2_BUILD_LOG"
  echo "default_workers_log=$DEFAULT_LOG"
  echo "workers1_log=$WORKERS1_LOG"

  if [[ "${REQUIRE_CLEAN:-0}" == "1" && "$classification" != "clean_both_modes" ]]; then
    exit "$failure_rc"
  fi
  if [[ "${REQUIRE_CURRENT_FRONTIER:-0}" == "1" && "$classification" != "current_0k_bn_frontier" ]]; then
    exit "$failure_rc"
  fi
  exit 0
}

print_header

if [[ -z "${STAGE1_COMPILER:-}" ]]; then
  set +e
  "$ROOT_DIR/scripts/build_stage1_original_cached.sh" "$STAGE1_MODE" "$STAGE1" --error-trace >"$STAGE1_LOG" 2>&1
  stage1_rc=$?
  set -e
  echo "stage1_build_rc=$stage1_rc"
  if [[ $stage1_rc -ne 0 || ! -x "$STAGE1" ]]; then
    echo "stage1_build_tail:"
    tail -80 "$STAGE1_LOG" || true
    finish_classification "stage1_build_fails" 8
  fi
else
  echo "stage1_build_rc=skipped"
  if [[ ! -x "$STAGE1" ]]; then
    echo "provided_stage1_not_executable=$STAGE1"
    finish_classification "stage1_build_fails" 8
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
    echo "s2_build_tail:"
    tail -100 "$S2_BUILD_LOG" || true
    finish_classification "s2_build_fails" 9
  fi
else
  echo "s2_build_rc=skipped"
  if [[ ! -x "$S2" ]]; then
    echo "provided_generated_s2_not_executable=$S2"
    finish_classification "s2_build_fails" 9
  fi
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$S2" "$SMOKE_TIMEOUT" "$SMOKE_MEM_MB" \
  "$SOURCE" -o "$DEFAULT_OUT" >"$DEFAULT_LOG" 2>&1
default_rc=$?
ADAMAS_LLVM_WORKERS=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$S2" "$SMOKE_TIMEOUT" "$SMOKE_MEM_MB" \
    "$SOURCE" -o "$WORKERS1_OUT" >"$WORKERS1_LOG" 2>&1
workers1_rc=$?
set -e

emit_mode_summary "default_workers" "$default_rc" "$DEFAULT_LOG" "$DEFAULT_OUT"
emit_mode_summary "workers1" "$workers1_rc" "$WORKERS1_LOG" "$WORKERS1_OUT"

default_after_lower_main=0
default_parallel_rand=0
default_memory_kill=0
workers1_after_lower_main=0
workers1_exit139=0
workers1_memory_kill=0
workers1_parallel_rand=0

log_has "pass3 after lower_main call" "$DEFAULT_LOG" && default_after_lower_main=1
log_has "parallel emission failed: Invalid bound for rand: 0" "$DEFAULT_LOG" && default_parallel_rand=1
log_has "[KILL] Memory limit:" "$DEFAULT_LOG" && default_memory_kill=1
log_has "pass3 after lower_main call" "$WORKERS1_LOG" && workers1_after_lower_main=1
log_has "[CRASH] Segfault (exit 139)" "$WORKERS1_LOG" && workers1_exit139=1
log_has "[KILL] Memory limit:" "$WORKERS1_LOG" && workers1_memory_kill=1
log_has "parallel emission failed: Invalid bound for rand: 0" "$WORKERS1_LOG" && workers1_parallel_rand=1

if [[ $default_rc -eq 0 && $workers1_rc -eq 0 && -x "$DEFAULT_OUT" && -x "$WORKERS1_OUT" ]]; then
  classification="clean_both_modes"
elif [[ $default_after_lower_main -eq 1 &&
        $default_parallel_rand -eq 1 &&
        $default_memory_kill -eq 1 &&
        $workers1_after_lower_main -eq 1 &&
        $workers1_exit139 -eq 1 &&
        $workers1_parallel_rand -eq 0 ]]; then
  classification="current_0k_bn_frontier"
elif [[ $default_after_lower_main -eq 1 || $workers1_after_lower_main -eq 1 ]]; then
  if [[ $default_rc -ne 0 && $workers1_rc -eq 0 ]]; then
    classification="worker_only_failure"
  else
    classification="llvm_entry_failure_after_lower_main"
  fi
else
  classification="pre_llvm_entry_failure"
fi

if [[ "$classification" != "clean_both_modes" || "${TAIL_ALWAYS:-0}" == "1" ]]; then
  echo "default_workers_tail:"
  tail -"$TAIL_LINES" "$DEFAULT_LOG" || true
  echo "workers1_tail:"
  tail -"$TAIL_LINES" "$WORKERS1_LOG" || true
fi

finish_classification "$classification" 9
