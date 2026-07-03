#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_finalize_to_s_classifier.sh [source.cr]

Build/use a generated s2 compiler and classify the current post-function-
emission finalization frontier. The focused question is whether the produced
compiler reaches LLVM finalization and crashes inside the in-memory
IO::Memory#to_s step, or whether the boundary has moved before/after that step.

Environment:
  KEEP_TMP=1
  STAGE1_COMPILER
  GENERATED_S2
  STAGE1_MODE=debug
  STAGE2_BUILD_TIMEOUT=600
  STAGE2_BUILD_MEM_MB=4096
  SMOKE_TIMEOUT=180
  SMOKE_MEM_MB=4096
  REQUIRE_CLASSIFICATION=1
  REQUIRE_RAW_DUMP=1

Classifications:
  select_finalize_to_s_stringification_frontier
  select_finalize_raw_dump_output_null_frontier
  select_finalize_raw_dump_output_object_id_frontier
  select_finalize_raw_dump_output_raw_header_frontier
  select_finalize_raw_dump_cast_frontier
  select_finalize_raw_dump_object_id_frontier
  select_finalize_raw_dump_receiver_null_frontier
  select_finalize_raw_dump_raw_header_frontier
  select_finalize_raw_dump_field_offset_missing_frontier
  select_finalize_raw_dump_field_offset_lookup_frontier
  select_finalize_raw_dump_raw_bytesize_frontier
  select_finalize_raw_dump_getter_bytesize_frontier
  post_to_s_frontier
  finalization_classifier_drift
  finalization_classifier_build_failed

This is a discriminator only. A stop-before-to_s clean result is not a fix and
does not license output/tail/string-buffer changes without the next owner-edge
receipt.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x /usr/bin/time ]]; then
  echo "classification=finalization_classifier_missing_time_l"
  echo "reason=/usr/bin/time_missing"
  exit 9
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-finalize-to-s.XXXXXX")"

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
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-180}"
SMOKE_MEM_MB="${SMOKE_MEM_MB:-4096}"

STAGE1="${STAGE1_COMPILER:-$TMP_DIR/adamas_stage1}"
S2="${GENERATED_S2:-$TMP_DIR/adamas_s2}"
STAGE1_LOG="$TMP_DIR/stage1_build.log"
S2_BUILD_LOG="$TMP_DIR/s2_build.log"
LEDGER="$TMP_DIR/runtime_ledger.tsv"
: >"$LEDGER"

echo "# Generated Stage Finalize-to-S Classifier"
echo "repo=$ROOT_DIR"
echo "source=$SOURCE"
echo "stage1=$STAGE1"
echo "generated_s2=$S2"
echo "stage2_build_timeout=$STAGE2_BUILD_TIMEOUT"
echo "stage2_build_mem_mb=$STAGE2_BUILD_MEM_MB"
echo "smoke_timeout=$SMOKE_TIMEOUT"
echo "smoke_mem_mb=$SMOKE_MEM_MB"
echo "require_classification=${REQUIRE_CLASSIFICATION:-0}"
echo "require_raw_dump=${REQUIRE_RAW_DUMP:-0}"

if [[ -z "${STAGE1_COMPILER:-}" ]]; then
  set +e
  "$ROOT_DIR/scripts/build_stage1_original_cached.sh" "$STAGE1_MODE" "$STAGE1" --error-trace >"$STAGE1_LOG" 2>&1
  stage1_rc=$?
  set -e
  echo "stage1_build_rc=$stage1_rc"
  if [[ $stage1_rc -ne 0 || ! -x "$STAGE1" ]]; then
    echo "classification=finalization_classifier_build_failed"
    echo "stage1_build_tail:"
    tail -100 "$STAGE1_LOG" || true
    exit 9
  fi
else
  echo "stage1_build_rc=skipped"
  if [[ ! -x "$STAGE1" ]]; then
    echo "provided_stage1_not_executable=$STAGE1"
    echo "classification=finalization_classifier_build_failed"
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
    echo "classification=finalization_classifier_build_failed"
    echo "s2_build_tail:"
    tail -120 "$S2_BUILD_LOG" || true
    exit 9
  fi
else
  echo "s2_build_rc=skipped"
  if [[ ! -x "$S2" ]]; then
    echo "provided_generated_s2_not_executable=$S2"
    echo "classification=finalization_classifier_build_failed"
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

ledger_count() {
  local tx="$1"
  local mode="$2"
  local row="$3"
  local pattern="${4:-}"
  if [[ -n "$pattern" ]]; then
    awk -F'\t' -v tx="$tx" -v mode="$mode" -v row="$row" -v pat="$pattern" '
      $1 == "GSETX" && $2 == tx && $3 == mode && $4 == row && index($5, pat) > 0 { count++ }
      END { print count + 0 }
    ' "$LEDGER" 2>/dev/null || echo 0
  else
    awk -F'\t' -v tx="$tx" -v mode="$mode" -v row="$row" '
      $1 == "GSETX" && $2 == tx && $3 == mode && $4 == row { count++ }
      END { print count + 0 }
    ' "$LEDGER" 2>/dev/null || echo 0
  fi
}

last_phase() {
  local tx="$1"
  local mode="$2"
  awk -F'\t' -v tx="$tx" -v mode="$mode" '
    $1 == "GSETX" && $2 == tx && $3 == mode && $4 == "llvm.generate_phase" {
      split($5, fields, " ")
      phase = ""
      for (i in fields) {
        if (index(fields[i], "phase=") == 1) {
          phase = substr(fields[i], 7)
        }
      }
      if (phase != "") last = phase
    }
    END { print last }
  ' "$LEDGER" 2>/dev/null || true
}

run_probe() {
  local label="$1"
  local extra_env="$2"
  local dump_path="${3:-}"
  local out_bin="$TMP_DIR/${label}_out"
  local log="$TMP_DIR/${label}.log"
  local tx="gsetx_${label}"
  local env_args=(
    "ADAMAS_GSETX_FUNCTION_EMISSION_OUTCOMES=1"
    "ADAMAS_GSETX_MEMORY_PHASES=1"
    "ADAMAS_GSETX_ID=$tx"
    "ADAMAS_GSETX_LEDGER=$LEDGER"
    "ADAMAS_GSETX_RUN_MODE=$label"
  )
  if [[ -n "$extra_env" ]]; then
    env_args+=("$extra_env=1")
  fi
  if [[ -n "$dump_path" ]]; then
    env_args+=(
      "ADAMAS_DUMP_LLVM_FINAL_BUFFER_BEFORE_TO_S=$dump_path"
      "ADAMAS_STOP_AFTER_LLVM_FINAL_BUFFER_DUMP=1"
    )
  fi

  set +e
  env "${env_args[@]}" \
    /usr/bin/time -l "$ROOT_DIR/scripts/run_safe.sh" "$S2" "$SMOKE_TIMEOUT" "$SMOKE_MEM_MB" \
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
  local emitted_count
  emitted_count="$(ledger_count "$tx" "$label" "llvm.function_emission_outcome" "status=emitted")"
  local started_count
  started_count="$(ledger_count "$tx" "$label" "llvm.function_emission_outcome" "status=started")"

  echo "${label}_rc=$rc"
  echo "${label}_run_safe_exit=${exit_code:-missing}"
  echo "${label}_peak_rss_bytes=${peak_bytes:-0}"
  echo "${label}_peak_rss_mb=$peak_mb"
  echo "${label}_started_outcomes=$started_count"
  echo "${label}_emitted_outcomes=$emitted_count"
  echo "${label}_sequential_done_rows=$(ledger_count "$tx" "$label" "llvm.function_emission_phase" "phase=sequential_done")"
  echo "${label}_function_emission_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=function_emission_done")"
  echo "${label}_tail_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=tail_done")"
  echo "${label}_metadata_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=metadata_done")"
  echo "${label}_type_name_table_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=type_name_table_done")"
  echo "${label}_dwarf_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=dwarf_done")"
  echo "${label}_finalize_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_enter")"
  echo "${label}_finalize_to_s_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_to_s_enter")"
  echo "${label}_finalize_to_s_stop_before_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_to_s_stop_before")"
  echo "${label}_finalize_to_s_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_to_s_done")"
  echo "${label}_finalize_raw_dump_cast_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_cast_enter")"
  echo "${label}_finalize_raw_dump_cast_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_cast_done")"
  echo "${label}_finalize_raw_dump_env_lookup_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_env_lookup_enter")"
  echo "${label}_finalize_raw_dump_env_lookup_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_env_lookup_done")"
  echo "${label}_finalize_raw_dump_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_enter")"
  echo "${label}_finalize_raw_dump_output_object_id_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_output_object_id_enter")"
  echo "${label}_finalize_raw_dump_output_object_id_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_output_object_id_done")"
  echo "${label}_finalize_raw_dump_output_null_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_output_null")"
  echo "${label}_finalize_raw_dump_output_raw_header_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_output_raw_header_enter")"
  echo "${label}_finalize_raw_dump_output_raw_header_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_output_raw_header_done")"
  echo "${label}_finalize_raw_dump_object_id_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_object_id_enter")"
  echo "${label}_finalize_raw_dump_object_id_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_object_id_done")"
  echo "${label}_finalize_raw_dump_receiver_null_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_receiver_null")"
  echo "${label}_finalize_raw_dump_raw_header_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_raw_header_enter")"
  echo "${label}_finalize_raw_dump_raw_header_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_raw_header_done")"
  echo "${label}_finalize_raw_dump_field_offset_lookup_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_field_offset_lookup_enter")"
  echo "${label}_finalize_raw_dump_field_offset_lookup_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_field_offset_lookup_done")"
  echo "${label}_finalize_raw_dump_field_offset_missing_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_field_offset_missing")"
  echo "${label}_finalize_raw_dump_raw_bytesize_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_raw_bytesize_enter")"
  echo "${label}_finalize_raw_dump_raw_bytesize_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_raw_bytesize_done")"
  echo "${label}_finalize_raw_dump_getter_bytesize_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_getter_bytesize_enter")"
  echo "${label}_finalize_raw_dump_bytesize_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_bytesize_done")"
  echo "${label}_finalize_raw_dump_buffer_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_buffer_done")"
  echo "${label}_finalize_raw_dump_write_enter_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_write_enter")"
  echo "${label}_finalize_raw_dump_done_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_done")"
  echo "${label}_finalize_raw_dump_failed_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_failed")"
  echo "${label}_finalize_raw_dump_stop_after_rows=$(ledger_count "$tx" "$label" "llvm.generate_phase" "phase=finalize_raw_dump_stop_after")"
  echo "${label}_last_phase=$(last_phase "$tx" "$label")"
  echo "${label}_log=$log"
}

run_probe "normal" ""
run_probe "stop_before_to_s" "ADAMAS_STOP_BEFORE_LLVM_FINALIZE_TO_S"
RAW_DUMP_FILE="$TMP_DIR/final_buffer_before_to_s.ll"
if [[ "${REQUIRE_RAW_DUMP:-0}" == "1" ]]; then
  run_probe "raw_dump_before_to_s" "" "$RAW_DUMP_FILE"
fi

# Read classification metrics directly from the ledger and run_safe logs.
normal_exit="$(run_safe_exit_code "$TMP_DIR/normal.log")"
stop_exit="$(run_safe_exit_code "$TMP_DIR/stop_before_to_s.log")"
normal_last="$(last_phase gsetx_normal normal)"
stop_last="$(last_phase gsetx_stop_before_to_s stop_before_to_s)"
normal_enter="$(ledger_count gsetx_normal normal llvm.generate_phase phase=finalize_to_s_enter)"
normal_done="$(ledger_count gsetx_normal normal llvm.generate_phase phase=finalize_to_s_done)"
normal_seq_done="$(ledger_count gsetx_normal normal llvm.function_emission_phase phase=sequential_done)"
normal_func_done="$(ledger_count gsetx_normal normal llvm.generate_phase phase=function_emission_done)"
stop_marker="$(ledger_count gsetx_stop_before_to_s stop_before_to_s llvm.generate_phase phase=finalize_to_s_stop_before)"
stop_done="$(ledger_count gsetx_stop_before_to_s stop_before_to_s llvm.generate_phase phase=finalize_to_s_done)"
raw_dump_exit=""
raw_dump_cast_enter=0
raw_dump_cast_done=0
raw_dump_env_enter=0
raw_dump_env_done=0
raw_dump_enter=0
raw_dump_output_object_id_enter=0
raw_dump_output_object_id_done=0
raw_dump_output_null=0
raw_dump_output_raw_header_enter=0
raw_dump_output_raw_header_done=0
raw_dump_object_id_enter=0
raw_dump_object_id_done=0
raw_dump_receiver_null=0
raw_dump_raw_header_enter=0
raw_dump_raw_header_done=0
raw_dump_field_offset_enter=0
raw_dump_field_offset_done=0
raw_dump_field_offset_missing=0
raw_dump_raw_bytesize_enter=0
raw_dump_raw_bytesize_done=0
raw_dump_getter_bytesize_enter=0
raw_dump_bytesize_done=0
raw_dump_buffer_done=0
raw_dump_write_enter=0
raw_dump_done=0
raw_dump_failed=0
raw_dump_stop=0
raw_dump_size=0
raw_dump_header=0
if [[ "${REQUIRE_RAW_DUMP:-0}" == "1" ]]; then
  raw_dump_exit="$(run_safe_exit_code "$TMP_DIR/raw_dump_before_to_s.log")"
  raw_dump_cast_enter="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_cast_enter)"
  raw_dump_cast_done="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_cast_done)"
  raw_dump_env_enter="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_env_lookup_enter)"
  raw_dump_env_done="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_env_lookup_done)"
  raw_dump_enter="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_enter)"
  raw_dump_output_object_id_enter="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_output_object_id_enter)"
  raw_dump_output_object_id_done="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_output_object_id_done)"
  raw_dump_output_null="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_output_null)"
  raw_dump_output_raw_header_enter="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_output_raw_header_enter)"
  raw_dump_output_raw_header_done="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_output_raw_header_done)"
  raw_dump_object_id_enter="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_object_id_enter)"
  raw_dump_object_id_done="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_object_id_done)"
  raw_dump_receiver_null="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_receiver_null)"
  raw_dump_raw_header_enter="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_raw_header_enter)"
  raw_dump_raw_header_done="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_raw_header_done)"
  raw_dump_field_offset_enter="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_field_offset_lookup_enter)"
  raw_dump_field_offset_done="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_field_offset_lookup_done)"
  raw_dump_field_offset_missing="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_field_offset_missing)"
  raw_dump_raw_bytesize_enter="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_raw_bytesize_enter)"
  raw_dump_raw_bytesize_done="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_raw_bytesize_done)"
  raw_dump_getter_bytesize_enter="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_getter_bytesize_enter)"
  raw_dump_bytesize_done="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_bytesize_done)"
  raw_dump_buffer_done="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_buffer_done)"
  raw_dump_write_enter="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_write_enter)"
  raw_dump_done="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_done)"
  raw_dump_failed="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_failed)"
  raw_dump_stop="$(ledger_count gsetx_raw_dump_before_to_s raw_dump_before_to_s llvm.generate_phase phase=finalize_raw_dump_stop_after)"
  if [[ -f "$RAW_DUMP_FILE" ]]; then
    raw_dump_size="$(wc -c <"$RAW_DUMP_FILE" | tr -d ' ')"
    if LC_ALL=C grep -a -q '^; ModuleID =' "$RAW_DUMP_FILE"; then
      raw_dump_header=1
    fi
  fi
fi

raw_dump_classification="not_requested"
if [[ "${REQUIRE_RAW_DUMP:-0}" == "1" ]]; then
  raw_dump_classification="raw_dump_classifier_drift"
  if [[ "${raw_dump_exit:-}" == "0" &&
        "$raw_dump_done" -gt 0 &&
        "$raw_dump_failed" -eq 0 &&
        "$raw_dump_stop" -gt 0 &&
        "$raw_dump_size" -gt 0 &&
        "$raw_dump_header" -eq 1 ]]; then
    raw_dump_classification="raw_dump_before_to_s_buffer_valid"
  elif [[ "$raw_dump_env_enter" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_pre_env_lookup_frontier"
  elif [[ "$raw_dump_env_done" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_env_lookup_frontier"
  elif [[ "$raw_dump_output_object_id_enter" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_pre_output_object_id_frontier"
  elif [[ "$raw_dump_output_object_id_done" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_output_object_id_frontier"
  elif [[ "$raw_dump_output_null" -gt 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_output_null_frontier"
  elif [[ "$raw_dump_output_raw_header_enter" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_pre_output_raw_header_frontier"
  elif [[ "$raw_dump_output_raw_header_done" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_output_raw_header_frontier"
  elif [[ "$raw_dump_cast_enter" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_pre_cast_frontier"
  elif [[ "$raw_dump_cast_done" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_cast_frontier"
  elif [[ "$raw_dump_enter" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_env_empty_or_pre_enter_frontier"
  elif [[ "$raw_dump_object_id_enter" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_pre_object_id_frontier"
  elif [[ "$raw_dump_object_id_done" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_object_id_frontier"
  elif [[ "$raw_dump_receiver_null" -gt 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_receiver_null_frontier"
  elif [[ "$raw_dump_raw_header_enter" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_pre_raw_header_frontier"
  elif [[ "$raw_dump_raw_header_done" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_raw_header_frontier"
  elif [[ "$raw_dump_field_offset_enter" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_pre_field_offset_lookup_frontier"
  elif [[ "$raw_dump_field_offset_missing" -gt 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_field_offset_missing_frontier"
  elif [[ "$raw_dump_field_offset_done" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_field_offset_lookup_frontier"
  elif [[ "$raw_dump_raw_bytesize_enter" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_pre_raw_bytesize_frontier"
  elif [[ "$raw_dump_raw_bytesize_done" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_raw_bytesize_frontier"
  elif [[ "$raw_dump_getter_bytesize_enter" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_pre_getter_bytesize_frontier"
  elif [[ "$raw_dump_bytesize_done" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_getter_bytesize_frontier"
  elif [[ "$raw_dump_buffer_done" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_buffer_frontier"
  elif [[ "$raw_dump_write_enter" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_pre_write_frontier"
  elif [[ "$raw_dump_done" -eq 0 && "$raw_dump_failed" -eq 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_write_frontier"
  elif [[ "$raw_dump_failed" -gt 0 ]]; then
    raw_dump_classification="select_finalize_raw_dump_write_failed"
  fi
fi

classification="finalization_classifier_drift"
if [[ "${normal_exit:-}" == "139" &&
      "$normal_seq_done" -gt 0 &&
      "$normal_func_done" -gt 0 &&
      "$normal_enter" -gt 0 &&
      "$normal_done" -eq 0 &&
      "${stop_exit:-}" == "0" &&
      "$stop_marker" -gt 0 &&
      "$stop_done" -eq 0 ]]; then
  classification="select_finalize_to_s_stringification_frontier"
elif [[ "$normal_done" -gt 0 ]]; then
  classification="post_to_s_frontier"
fi

echo "normal_last_phase=${normal_last:-missing}"
echo "stop_before_to_s_last_phase=${stop_last:-missing}"
if [[ "${REQUIRE_RAW_DUMP:-0}" == "1" ]]; then
  echo "raw_dump_before_to_s_exit=${raw_dump_exit:-missing}"
  echo "raw_dump_before_to_s_cast_enter_rows=$raw_dump_cast_enter"
  echo "raw_dump_before_to_s_cast_done_rows=$raw_dump_cast_done"
  echo "raw_dump_before_to_s_env_lookup_enter_rows=$raw_dump_env_enter"
  echo "raw_dump_before_to_s_env_lookup_done_rows=$raw_dump_env_done"
  echo "raw_dump_before_to_s_enter_rows=$raw_dump_enter"
  echo "raw_dump_before_to_s_output_object_id_enter_rows=$raw_dump_output_object_id_enter"
  echo "raw_dump_before_to_s_output_object_id_done_rows=$raw_dump_output_object_id_done"
  echo "raw_dump_before_to_s_output_null_rows=$raw_dump_output_null"
  echo "raw_dump_before_to_s_output_raw_header_enter_rows=$raw_dump_output_raw_header_enter"
  echo "raw_dump_before_to_s_output_raw_header_done_rows=$raw_dump_output_raw_header_done"
  echo "raw_dump_before_to_s_object_id_enter_rows=$raw_dump_object_id_enter"
  echo "raw_dump_before_to_s_object_id_done_rows=$raw_dump_object_id_done"
  echo "raw_dump_before_to_s_receiver_null_rows=$raw_dump_receiver_null"
  echo "raw_dump_before_to_s_raw_header_enter_rows=$raw_dump_raw_header_enter"
  echo "raw_dump_before_to_s_raw_header_done_rows=$raw_dump_raw_header_done"
  echo "raw_dump_before_to_s_field_offset_lookup_enter_rows=$raw_dump_field_offset_enter"
  echo "raw_dump_before_to_s_field_offset_lookup_done_rows=$raw_dump_field_offset_done"
  echo "raw_dump_before_to_s_field_offset_missing_rows=$raw_dump_field_offset_missing"
  echo "raw_dump_before_to_s_raw_bytesize_enter_rows=$raw_dump_raw_bytesize_enter"
  echo "raw_dump_before_to_s_raw_bytesize_done_rows=$raw_dump_raw_bytesize_done"
  echo "raw_dump_before_to_s_getter_bytesize_enter_rows=$raw_dump_getter_bytesize_enter"
  echo "raw_dump_before_to_s_bytesize_done_rows=$raw_dump_bytesize_done"
  echo "raw_dump_before_to_s_buffer_done_rows=$raw_dump_buffer_done"
  echo "raw_dump_before_to_s_write_enter_rows=$raw_dump_write_enter"
  echo "raw_dump_before_to_s_done_rows=$raw_dump_done"
  echo "raw_dump_before_to_s_failed_rows=$raw_dump_failed"
  echo "raw_dump_before_to_s_stop_after_rows=$raw_dump_stop"
  echo "raw_dump_before_to_s_size=$raw_dump_size"
  echo "raw_dump_before_to_s_header=$raw_dump_header"
  echo "raw_dump_before_to_s_file=$RAW_DUMP_FILE"
  echo "raw_dump_classification=$raw_dump_classification"
fi
echo "classification=$classification"
echo "ledger=$LEDGER"

if [[ "${REQUIRE_CLASSIFICATION:-0}" == "1" && "$classification" != "select_finalize_to_s_stringification_frontier" ]]; then
  echo "normal_log_tail:"
  tail -80 "$TMP_DIR/normal.log" || true
  echo "stop_before_to_s_log_tail:"
  tail -80 "$TMP_DIR/stop_before_to_s.log" || true
  exit 9
fi

if [[ "${REQUIRE_RAW_DUMP:-0}" == "1" ]]; then
  if [[ "$raw_dump_classification" == "raw_dump_classifier_drift" ]]; then
    echo "raw_dump_before_to_s_log_tail:"
    tail -80 "$TMP_DIR/raw_dump_before_to_s.log" || true
    exit 9
  fi
fi
