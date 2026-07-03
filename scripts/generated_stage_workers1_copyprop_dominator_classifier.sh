#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_workers1_copyprop_dominator_classifier.sh [source.cr]

Build/use a fresh generated s2 compiler, confirm the selected workers=1
CopyPropagation apply_build_dominators resource lane, then classify which
dominance-build substep first crosses the OS-RSS threshold.

This is a post-0k-DW subowner selector. It runs probes with
ADAMAS_LLVM_WORKERS=1, ADAMAS_STOP_AFTER_MIR_OPT=1,
ADAMAS_MIR_OPT_THROUGH_PASS=copy_propagation,
ADAMAS_CP_THROUGH_PHASE=apply_build_dominators, and
ADAMAS_CP_DOM_THROUGH_STEP=<step>. The compiler stops after the whole serial
MIR optimization loop, so the measurement is module-wide.

Environment:
  KEEP_TMP=1                 Keep temp dirs for manual inspection.
  REQUIRE_CLASSIFICATION=1   Exit nonzero unless a terminal classification is
                             produced.
  REQUIRE_DOMINATOR=1        Exit nonzero unless a dominance subowner lane is
                             selected, the lane is clean, or the selected lane
                             decays.
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
  select_workers1_copyprop_dom_build_def_maps_resource_lane
  select_workers1_copyprop_dom_skip_check_resource_lane
  select_workers1_copyprop_dom_compute_dominance_info_resource_lane
  workers1_copyprop_dom_after_step_resource_boundary
  workers1_copyprop_dominator_lane_clean
  workers1_copyprop_dominator_lane_decayed
  workers1_copyprop_dominator_classifier_build_failed
  workers1_copyprop_dominator_classifier_missing_time_l
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x /usr/bin/time ]]; then
  echo "classification=workers1_copyprop_dominator_classifier_missing_time_l"
  echo "reason=/usr/bin/time_missing"
  exit 9
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-workers1-copyprop-dom.XXXXXX")"
PHASE_TMP=""
PASS_TMP=""
SUBPHASE_TMP=""
ENTRY_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
    [[ -n "$PHASE_TMP" ]] && echo "kept_phase_tmp=$PHASE_TMP"
    [[ -n "$PASS_TMP" ]] && echo "kept_pass_tmp=$PASS_TMP"
    [[ -n "$SUBPHASE_TMP" ]] && echo "kept_subphase_tmp=$SUBPHASE_TMP"
    [[ -n "$ENTRY_TMP" ]] && echo "kept_entry_tmp=$ENTRY_TMP"
  else
    if [[ -n "$ENTRY_TMP" && "$ENTRY_TMP" == "$ROOT_DIR/tmp/generated-stage-llvm-entry."* ]]; then
      rm -rf "$ENTRY_TMP"
    fi
    if [[ -n "$SUBPHASE_TMP" && "$SUBPHASE_TMP" == "$ROOT_DIR/tmp/generated-stage-workers1-mir-subphase."* ]]; then
      rm -rf "$SUBPHASE_TMP"
    fi
    if [[ -n "$PASS_TMP" && "$PASS_TMP" == "$ROOT_DIR/tmp/generated-stage-workers1-mir-opt-pass."* ]]; then
      rm -rf "$PASS_TMP"
    fi
    if [[ -n "$PHASE_TMP" && "$PHASE_TMP" == "$ROOT_DIR/tmp/generated-stage-workers1-copyprop-phase."* ]]; then
      rm -rf "$PHASE_TMP"
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
PHASE_OUT="$TMP_DIR/generated_stage_workers1_copyprop_phase.out"

echo "# Generated Stage Workers1 CopyPropagation Dominator Classifier"
echo "repo=$ROOT_DIR"
echo "source=$SOURCE"
echo "high_rss_mb=$HIGH_RSS_MB"
echo "smoke_timeout=$SMOKE_TIMEOUT"
echo "smoke_mem_mb=$SMOKE_MEM_MB"
echo "require_classification=${REQUIRE_CLASSIFICATION:-0}"
echo "require_dominator=${REQUIRE_DOMINATOR:-0}"

set +e
KEEP_TMP=1 \
REQUIRE_CLASSIFICATION=1 \
REQUIRE_PHASE=1 \
STAGE1_COMPILER="${STAGE1_COMPILER:-}" \
GENERATED_S2="${GENERATED_S2:-}" \
STAGE1_MODE="${STAGE1_MODE:-debug}" \
STAGE2_BUILD_TIMEOUT="${STAGE2_BUILD_TIMEOUT:-300}" \
STAGE2_BUILD_MEM_MB="${STAGE2_BUILD_MEM_MB:-4096}" \
SMOKE_TIMEOUT="$SMOKE_TIMEOUT" \
SMOKE_MEM_MB="$SMOKE_MEM_MB" \
TAIL_LINES="$TAIL_LINES" \
  "$ROOT_DIR/scripts/generated_stage_workers1_copyprop_phase_classifier.sh" "$SOURCE" >"$PHASE_OUT" 2>&1
phase_rc=$?
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

PHASE_TMP="$(value_of_file kept_tmp "$PHASE_OUT")"
PASS_TMP="$(value_of_file kept_pass_tmp "$PHASE_OUT")"
SUBPHASE_TMP="$(value_of_file kept_subphase_tmp "$PHASE_OUT")"
ENTRY_TMP="$(value_of_file kept_entry_tmp "$PHASE_OUT")"
S2_PATH="$(value_of_file generated_s2 "$PHASE_OUT")"
phase_classification="$(value_of_file classification "$PHASE_OUT")"

echo "phase_rc=$phase_rc"
echo "phase.classification=$phase_classification"
echo "phase.phase_apply_build_dominators_peak_rss_mb=$(value_of_file phase_apply_build_dominators_peak_rss_mb "$PHASE_OUT")"
echo "phase.phase_apply_build_dominators_memory_kill=$(value_of_file phase_apply_build_dominators_memory_kill "$PHASE_OUT")"
echo "phase_log=$PHASE_OUT"
echo "generated_s2=$S2_PATH"

if [[ "$phase_rc" -ne 0 || ! -x "$S2_PATH" ]]; then
  echo "classification=workers1_copyprop_dominator_classifier_build_failed"
  echo "phase_tail:"
  tail -120 "$PHASE_OUT" || true
  exit 9
fi

if [[ "$phase_classification" != "select_workers1_copyprop_apply_build_dominators_resource_lane" ]]; then
  echo "classification=workers1_copyprop_dominator_lane_decayed"
  if [[ "${REQUIRE_DOMINATOR:-0}" == "1" ]]; then
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

run_step_probe() {
  local step="$1"
  local out_bin="$TMP_DIR/step_${step}.out"
  local log="$TMP_DIR/step_${step}.log"

  set +e
  env ADAMAS_LLVM_WORKERS=1 ADAMAS_STOP_AFTER_MIR_OPT=1 \
      ADAMAS_MIR_OPT_THROUGH_PASS=copy_propagation \
      ADAMAS_CP_THROUGH_PHASE=apply_build_dominators \
      ADAMAS_CP_DOM_THROUGH_STEP="$step" \
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

  echo "step_${step}_rc=$rc"
  echo "step_${step}_run_safe_exit=${exit_code:-missing}"
  echo "step_${step}_peak_rss_bytes=${peak_bytes:-0}"
  echo "step_${step}_peak_rss_mb=$peak_mb"
  echo "step_${step}_memory_kill=$memory_kill"
  echo "step_${step}_memory_kill_kb=${kill_kb:-0}"
  echo "step_${step}_log=$log"
}

SUMMARY="$TMP_DIR/dominator_summary.out"
steps=(
  build_def_maps
  skip_check
  compute_dominance_info
)

{
  for step in "${steps[@]}"; do
    run_step_probe "$step"
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

classification="workers1_copyprop_dominator_lane_clean"
for step in "${steps[@]}"; do
  rc="$(read_metric "step_${step}_rc" "$SUMMARY")"
  peak="$(read_metric "step_${step}_peak_rss_mb" "$SUMMARY")"
  kill="$(read_metric "step_${step}_memory_kill" "$SUMMARY")"
  if probe_bad "${rc:-99}" "${peak:-999999}" "${kill:-1}"; then
    classification="select_workers1_copyprop_dom_${step}_resource_lane"
    break
  fi
done

if [[ "$classification" == "workers1_copyprop_dominator_lane_clean" ]]; then
  full_kill="$(value_of_file phase_apply_build_dominators_memory_kill "$PHASE_OUT")"
  full_peak="$(value_of_file phase_apply_build_dominators_peak_rss_mb "$PHASE_OUT")"
  if [[ "${full_kill:-0}" == "1" || "${full_peak:-0}" -ge "$HIGH_RSS_MB" ]]; then
    classification="workers1_copyprop_dom_after_step_resource_boundary"
  fi
fi

echo "classification=$classification"

if [[ "${REQUIRE_CLASSIFICATION:-0}" == "1" ]]; then
  case "$classification" in
    select_workers1_copyprop_dom_build_def_maps_resource_lane|select_workers1_copyprop_dom_skip_check_resource_lane|select_workers1_copyprop_dom_compute_dominance_info_resource_lane|workers1_copyprop_dom_after_step_resource_boundary|workers1_copyprop_dominator_lane_clean|workers1_copyprop_dominator_lane_decayed)
      ;;
    *)
      exit 9
      ;;
  esac
fi

if [[ "${REQUIRE_DOMINATOR:-0}" == "1" ]]; then
  case "$classification" in
    select_workers1_copyprop_dom_build_def_maps_resource_lane|select_workers1_copyprop_dom_skip_check_resource_lane|select_workers1_copyprop_dom_compute_dominance_info_resource_lane|workers1_copyprop_dom_after_step_resource_boundary|workers1_copyprop_dominator_lane_clean)
      ;;
    *)
      exit 9
      ;;
  esac
fi
