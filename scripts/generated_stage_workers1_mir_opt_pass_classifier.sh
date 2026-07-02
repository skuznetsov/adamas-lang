#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_workers1_mir_opt_pass_classifier.sh [source.cr]

Build/use a fresh generated s2 compiler, confirm the selected workers=1 MIR
optimization resource lane, then classify which MIR optimization pass first
crosses the OS-RSS threshold.

This is a post-0k-DU pass-level selector. It runs each probe with
ADAMAS_LLVM_WORKERS=1, ADAMAS_STOP_AFTER_MIR_OPT=1, and
ADAMAS_MIR_OPT_THROUGH_PASS=<pass>, so every MIR function is optimized only
through the selected pass before the compiler stops after the serial MIR
optimization loop.

Environment:
  KEEP_TMP=1                 Keep temp dirs for manual inspection.
  REQUIRE_CLASSIFICATION=1   Exit nonzero unless a terminal classification is
                             produced.
  REQUIRE_PASS=1             Exit nonzero unless a pass lane is selected,
                             the lane is clean, or the selected lane decays.
  HIGH_RSS_MB                Peak RSS threshold for "high" (default: 3072).
  STAGE1_COMPILER            Pass-through to generated-stage classifiers.
  GENERATED_S2               Pass-through to generated-stage classifiers.
  STAGE1_MODE                Pass-through stage1 mode (default inherited).
  STAGE2_BUILD_TIMEOUT       Pass-through generated s2 build timeout.
  STAGE2_BUILD_MEM_MB        Pass-through generated s2 build RSS cap.
  SMOKE_TIMEOUT              Stop-gate compile timeout (default: 120).
  SMOKE_MEM_MB               Stop-gate compile RSS cap (default: 4096).
  TAIL_LINES                 Nested classifier tail lines (default: 40).

Classifications:
  select_workers1_mir_opt_constant_folding_resource_lane
  select_workers1_mir_opt_local_cse_resource_lane
  select_workers1_mir_opt_rc_elision_resource_lane
  select_workers1_mir_opt_copy_propagation_resource_lane
  select_workers1_mir_opt_peephole_resource_lane
  select_workers1_mir_opt_lock_elision_resource_lane
  select_workers1_mir_opt_dce_resource_lane
  select_workers1_mir_opt_dce_2_resource_lane
  workers1_mir_opt_after_pass_resource_boundary
  workers1_mir_opt_pass_lane_clean
  workers1_mir_opt_pass_lane_decayed
  workers1_mir_opt_pass_classifier_build_failed
  workers1_mir_opt_pass_classifier_missing_time_l
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x /usr/bin/time ]]; then
  echo "classification=workers1_mir_opt_pass_classifier_missing_time_l"
  echo "reason=/usr/bin/time_missing"
  exit 9
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-workers1-mir-opt-pass.XXXXXX")"
NESTED_TMP=""
ENTRY_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
    [[ -n "$NESTED_TMP" ]] && echo "kept_subphase_tmp=$NESTED_TMP"
    [[ -n "$ENTRY_TMP" ]] && echo "kept_entry_tmp=$ENTRY_TMP"
  else
    if [[ -n "$ENTRY_TMP" && "$ENTRY_TMP" == "$ROOT_DIR/tmp/generated-stage-llvm-entry."* ]]; then
      rm -rf "$ENTRY_TMP"
    fi
    if [[ -n "$NESTED_TMP" && "$NESTED_TMP" == "$ROOT_DIR/tmp/generated-stage-workers1-mir-subphase."* ]]; then
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
SUBPHASE_OUT="$TMP_DIR/generated_stage_workers1_mir_subphase.out"

echo "# Generated Stage Workers1 MIR Optimization Pass Classifier"
echo "repo=$ROOT_DIR"
echo "source=$SOURCE"
echo "high_rss_mb=$HIGH_RSS_MB"
echo "smoke_timeout=$SMOKE_TIMEOUT"
echo "smoke_mem_mb=$SMOKE_MEM_MB"
echo "require_classification=${REQUIRE_CLASSIFICATION:-0}"
echo "require_pass=${REQUIRE_PASS:-0}"

set +e
KEEP_TMP=1 \
REQUIRE_CLASSIFICATION=1 \
REQUIRE_SUBPHASE=1 \
STAGE1_COMPILER="${STAGE1_COMPILER:-}" \
GENERATED_S2="${GENERATED_S2:-}" \
STAGE1_MODE="${STAGE1_MODE:-debug}" \
STAGE2_BUILD_TIMEOUT="${STAGE2_BUILD_TIMEOUT:-300}" \
STAGE2_BUILD_MEM_MB="${STAGE2_BUILD_MEM_MB:-4096}" \
SMOKE_TIMEOUT="$SMOKE_TIMEOUT" \
SMOKE_MEM_MB="$SMOKE_MEM_MB" \
TAIL_LINES="$TAIL_LINES" \
  "$ROOT_DIR/scripts/generated_stage_workers1_mir_subphase_classifier.sh" "$SOURCE" >"$SUBPHASE_OUT" 2>&1
subphase_rc=$?
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

NESTED_TMP="$(value_of_file kept_tmp "$SUBPHASE_OUT")"
ENTRY_TMP="$(value_of_file kept_classifier_tmp "$SUBPHASE_OUT")"
entry_log="$(value_of_file entry_classifier_log "$SUBPHASE_OUT")"
S2_PATH=""
if [[ -n "$entry_log" && -f "$entry_log" ]]; then
  S2_PATH="$(value_of_file generated_s2 "$entry_log")"
fi

subphase_classification="$(value_of_file classification "$SUBPHASE_OUT")"
echo "subphase_rc=$subphase_rc"
echo "subphase.classification=$subphase_classification"
echo "subphase.stage1_mir_peak_rss_mb=$(value_of_file stage1_mir_peak_rss_mb "$SUBPHASE_OUT")"
echo "subphase.s2_mir_bodies_peak_rss_mb=$(value_of_file s2_mir_bodies_peak_rss_mb "$SUBPHASE_OUT")"
echo "subphase.s2_mir_opt_peak_rss_mb=$(value_of_file s2_mir_opt_peak_rss_mb "$SUBPHASE_OUT")"
echo "subphase.s2_mir_opt_memory_kill=$(value_of_file s2_mir_opt_memory_kill "$SUBPHASE_OUT")"
echo "subphase_log=$SUBPHASE_OUT"
echo "entry_classifier_log=$entry_log"
echo "generated_s2=$S2_PATH"

if [[ "$subphase_rc" -ne 0 || ! -x "$S2_PATH" ]]; then
  echo "classification=workers1_mir_opt_pass_classifier_build_failed"
  echo "subphase_tail:"
  tail -120 "$SUBPHASE_OUT" || true
  exit 9
fi

if [[ "$subphase_classification" != "select_workers1_mir_optimization_resource_lane" ]]; then
  echo "classification=workers1_mir_opt_pass_lane_decayed"
  if [[ "${REQUIRE_PASS:-0}" == "1" ]]; then
    exit 9
  fi
  exit 0
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

run_pass_probe() {
  local pass="$1"
  local out_bin="$TMP_DIR/pass_${pass}.out"
  local log="$TMP_DIR/pass_${pass}.log"

  set +e
  env ADAMAS_LLVM_WORKERS=1 ADAMAS_STOP_AFTER_MIR_OPT=1 ADAMAS_MIR_OPT_THROUGH_PASS="$pass" \
    /usr/bin/time -l "$ROOT_DIR/scripts/run_safe.sh" "$S2_PATH" "$SMOKE_TIMEOUT" "$SMOKE_MEM_MB" \
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

  echo "pass_${pass}_rc=$rc"
  echo "pass_${pass}_run_safe_exit=${exit_code:-missing}"
  echo "pass_${pass}_peak_rss_bytes=${peak_bytes:-0}"
  echo "pass_${pass}_peak_rss_mb=$peak_mb"
  echo "pass_${pass}_memory_kill=$memory_kill"
  echo "pass_${pass}_memory_kill_kb=${kill_kb:-0}"
  echo "pass_${pass}_log=$log"
}

SUMMARY="$TMP_DIR/pass_summary.out"
passes=(
  constant_folding
  local_cse
  rc_elision
  copy_propagation
  peephole
  lock_elision
  dce
  dce_2
)

{
  for pass in "${passes[@]}"; do
    run_pass_probe "$pass"
  done
} >"$SUMMARY"

cat "$SUMMARY"

read_metric() {
  local key="$1"
  local file="$2"
  awk -F= -v k="$key" '$1 == k { print $2; exit }' "$file"
}

probe_bad() {
  local rc="$1"
  local peak="$2"
  local kill="$3"
  [[ "${rc:-99}" -ne 0 || "${kill:-1}" == "1" || "${peak:-999999}" -ge "$HIGH_RSS_MB" ]]
}

classification="workers1_mir_opt_pass_lane_clean"
for pass in "${passes[@]}"; do
  rc="$(read_metric "pass_${pass}_rc" "$SUMMARY")"
  peak="$(read_metric "pass_${pass}_peak_rss_mb" "$SUMMARY")"
  kill="$(read_metric "pass_${pass}_memory_kill" "$SUMMARY")"
  if probe_bad "${rc:-99}" "${peak:-999999}" "${kill:-1}"; then
    classification="select_workers1_mir_opt_${pass}_resource_lane"
    break
  fi
done

if [[ "$classification" == "workers1_mir_opt_pass_lane_clean" ]]; then
  full_kill="$(value_of_file s2_mir_opt_memory_kill "$SUBPHASE_OUT")"
  full_peak="$(value_of_file s2_mir_opt_peak_rss_mb "$SUBPHASE_OUT")"
  if [[ "${full_kill:-0}" == "1" || "${full_peak:-0}" -ge "$HIGH_RSS_MB" ]]; then
    classification="workers1_mir_opt_after_pass_resource_boundary"
  fi
fi

echo "classification=$classification"

if [[ "${REQUIRE_CLASSIFICATION:-0}" == "1" ]]; then
  case "$classification" in
    select_workers1_mir_opt_constant_folding_resource_lane|select_workers1_mir_opt_local_cse_resource_lane|select_workers1_mir_opt_rc_elision_resource_lane|select_workers1_mir_opt_copy_propagation_resource_lane|select_workers1_mir_opt_peephole_resource_lane|select_workers1_mir_opt_lock_elision_resource_lane|select_workers1_mir_opt_dce_resource_lane|select_workers1_mir_opt_dce_2_resource_lane|workers1_mir_opt_after_pass_resource_boundary|workers1_mir_opt_pass_lane_clean|workers1_mir_opt_pass_lane_decayed)
      ;;
    *)
      exit 9
      ;;
  esac
fi

if [[ "${REQUIRE_PASS:-0}" == "1" ]]; then
  case "$classification" in
    select_workers1_mir_opt_constant_folding_resource_lane|select_workers1_mir_opt_local_cse_resource_lane|select_workers1_mir_opt_rc_elision_resource_lane|select_workers1_mir_opt_copy_propagation_resource_lane|select_workers1_mir_opt_peephole_resource_lane|select_workers1_mir_opt_lock_elision_resource_lane|select_workers1_mir_opt_dce_resource_lane|select_workers1_mir_opt_dce_2_resource_lane|workers1_mir_opt_after_pass_resource_boundary|workers1_mir_opt_pass_lane_clean)
      ;;
    *)
      exit 9
      ;;
  esac
fi
