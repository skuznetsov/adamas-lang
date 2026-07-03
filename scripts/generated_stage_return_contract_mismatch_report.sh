#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_return_contract_mismatch_report.sh

Classify the current post-0k-EN generated-stage llc mismatch as the executable
red gate for the next FunctionReturnAvailability / LoweredFunctionReturnContract
slice. This script is a selector only: it does not prove the root fixed and does
not make s2b/s3b green.

Environment:
  CLASSIFIER_LOG=<path>  Reuse an existing generated_stage_finalize_to_s log.
  NORMAL_LL=<path>       Override the normal generated LLVM IR path.
  KEEP_TMP=1            Keep temporary classifier output when this script runs it.
  REQUIRE_SELECTED=1    Exit nonzero unless the function-return-contract gate is selected.

When CLASSIFIER_LOG is not provided, this script runs:
  REQUIRE_RAW_DUMP=1 REQUIRE_CLASSIFICATION=1
    scripts/generated_stage_finalize_to_s_classifier.sh
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
WORK_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-return-contract.XXXXXX")"
CLASSIFIER_WAS_RUN=0
CLASSIFIER_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$WORK_DIR"
    if [[ -n "$CLASSIFIER_TMP" ]]; then
      echo "kept_classifier_tmp=$CLASSIFIER_TMP"
    fi
  else
    rm -rf "$WORK_DIR"
    if [[ "$CLASSIFIER_WAS_RUN" == "1" &&
          -n "$CLASSIFIER_TMP" &&
          "$CLASSIFIER_TMP" == "$ROOT_DIR"/tmp/generated-stage-finalize-to-s.* ]]; then
      rm -rf "$CLASSIFIER_TMP"
    fi
  fi
}
trap cleanup EXIT

kv() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    index($0, key "=") == 1 {
      value = substr($0, length(key) + 2)
    }
    END { print value }
  ' "$file" 2>/dev/null || true
}

if [[ -n "${CLASSIFIER_LOG:-}" ]]; then
  if [[ ! -f "$CLASSIFIER_LOG" ]]; then
    echo "classification=function_return_contract_classifier_missing_log"
    echo "reason=classifier_log_not_found"
    echo "classifier_log=$CLASSIFIER_LOG"
    exit 9
  fi
  classifier_rc="skipped"
else
  CLASSIFIER_LOG="$WORK_DIR/finalize_classifier.log"
  CLASSIFIER_WAS_RUN=1
  set +e
  env KEEP_TMP=1 REQUIRE_RAW_DUMP=1 REQUIRE_CLASSIFICATION=1 \
    "$ROOT_DIR/scripts/generated_stage_finalize_to_s_classifier.sh" \
    >"$CLASSIFIER_LOG" 2>&1
  classifier_rc=$?
  set -e
  CLASSIFIER_TMP="$(kv kept_tmp "$CLASSIFIER_LOG")"
fi

if [[ -z "$CLASSIFIER_TMP" ]]; then
  CLASSIFIER_TMP="$(kv kept_tmp "$CLASSIFIER_LOG")"
fi

upstream_classification="$(kv classification "$CLASSIFIER_LOG")"
header_shape="$(kv normal_string_header_size_global_shape "$CLASSIFIER_LOG")"
header_line="$(kv normal_string_header_size_global_line "$CLASSIFIER_LOG")"
llc_mismatch="$(kv normal_llc_type_mismatch "$CLASSIFIER_LOG")"
llc_file="$(kv normal_llc_error_file "$CLASSIFIER_LOG")"
llc_line="$(kv normal_llc_error_line "$CLASSIFIER_LOG")"
llc_value="$(kv normal_llc_error_value "$CLASSIFIER_LOG")"
llc_defined="$(kv normal_llc_error_defined_type "$CLASSIFIER_LOG")"
llc_expected="$(kv normal_llc_error_expected_type "$CLASSIFIER_LOG")"
raw_dump_classification="$(kv raw_dump_classification "$CLASSIFIER_LOG")"

normal_ll="${NORMAL_LL:-}"
if [[ -z "$normal_ll" && -n "$llc_file" ]]; then
  normal_ll="$llc_file"
fi
if [[ -z "$normal_ll" && -n "$CLASSIFIER_TMP" ]]; then
  normal_ll="$CLASSIFIER_TMP/normal_out.ll"
fi

bad_function_line=""
bad_function_symbol=""
callee_candidate="missing"
error_window_has_value=0
error_window_has_ptr_use=0
function_window_has_read_char=0
function_window_has_gets_slow=0

if [[ -n "$normal_ll" && -f "$normal_ll" && "$llc_line" =~ ^[0-9]+$ ]]; then
  bad_function_line="$(
    awk -v target_line="$llc_line" '
      NR <= target_line && /^define / { fn = $0 }
      END { print fn }
    ' "$normal_ll"
  )"
  if [[ -n "$bad_function_line" ]]; then
    bad_function_symbol="$(
      printf '%s\n' "$bad_function_line" |
        sed -E 's/^define[^(]*@([^ (]+).*/\1/'
    )"
  fi

  start=$(( llc_line > 160 ? llc_line - 160 : 1 ))
  end=$(( llc_line + 40 ))
  window="$WORK_DIR/normal_ll_window.ll"
  sed -n "${start},${end}p" "$normal_ll" >"$window"

  if LC_ALL=C grep -a -F -q "$llc_value" "$window"; then
    error_window_has_value=1
  fi
  if LC_ALL=C grep -a -E -q "(getelementptr|load|store|call).*${llc_value}|${llc_value}.*(getelementptr|load|store|call)" "$window"; then
    error_window_has_ptr_use=1
  fi
  if LC_ALL=C grep -a -q 'read_char_with_bytesize' "$window"; then
    function_window_has_read_char=1
    callee_candidate="IO#read_char_with_bytesize"
  fi
  if LC_ALL=C grep -a -q 'IO\$Hgets_slow' "$window" || printf '%s\n' "$bad_function_symbol" | LC_ALL=C grep -a -q 'IO\$Hgets_slow'; then
    function_window_has_gets_slow=1
  fi
fi

classification="function_return_contract_classifier_drift"
selection_status="rejected"
reason="unknown"

if [[ "${classifier_rc:-0}" != "0" && "${classifier_rc:-skipped}" != "skipped" ]]; then
  reason="upstream_classifier_failed"
elif [[ "$upstream_classification" != "post_to_s_llc_type_mismatch_frontier" ]]; then
  reason="upstream_classification_not_post_to_s_llc_type_mismatch"
elif [[ "$header_shape" != "i32_12" ]]; then
  reason="string_header_size_scalar_global_not_preserved"
elif [[ "$raw_dump_classification" != "raw_dump_before_to_s_buffer_valid" ]]; then
  reason="raw_dump_not_buffer_valid"
elif [[ "$llc_mismatch" != "1" ]]; then
  reason="normal_llc_type_mismatch_missing"
elif [[ "$llc_value" != "%r18.fromslot.1" ]]; then
  reason="llc_value_not_current_l20_value"
elif [[ "$llc_defined" != "i64" || "$llc_expected" != "ptr" ]]; then
  reason="llc_defined_expected_not_i64_ptr"
elif [[ "$function_window_has_gets_slow" -ne 1 ]]; then
  reason="bad_function_not_io_gets_slow"
elif [[ "$function_window_has_read_char" -ne 1 ]]; then
  reason="callee_read_char_with_bytesize_not_in_window"
else
  classification="function_return_contract_mismatch_frontier"
  selection_status="eligible_function_return_contract_mismatch"
  reason="selected"
fi

echo "# Generated Stage Return Contract Mismatch Report"
echo "repo=$ROOT_DIR"
echo "classifier_log=$CLASSIFIER_LOG"
echo "classifier_rc=${classifier_rc:-skipped}"
echo "classifier_tmp=${CLASSIFIER_TMP:-missing}"
echo "normal_ll=${normal_ll:-missing}"
echo "upstream_classification=$upstream_classification"
echo "normal_string_header_size_global_shape=$header_shape"
if [[ -n "$header_line" ]]; then
  echo "normal_string_header_size_global_line=$header_line"
fi
echo "raw_dump_classification=${raw_dump_classification:-missing}"
echo "normal_llc_type_mismatch=${llc_mismatch:-missing}"
echo "normal_llc_error_file=${llc_file:-missing}"
echo "normal_llc_error_line=${llc_line:-missing}"
echo "normal_llc_error_value=${llc_value:-missing}"
echo "normal_llc_error_defined_type=${llc_defined:-missing}"
echo "normal_llc_error_expected_type=${llc_expected:-missing}"
echo "bad_function_symbol=${bad_function_symbol:-missing}"
echo "callee_candidate=$callee_candidate"
echo "error_window_has_value=$error_window_has_value"
echo "error_window_has_ptr_use=$error_window_has_ptr_use"
echo "function_window_has_gets_slow=$function_window_has_gets_slow"
echo "function_window_has_read_char=$function_window_has_read_char"
echo "selection_status=$selection_status"
echo "classification=$classification"
echo "reason=$reason"

if [[ "${REQUIRE_SELECTED:-0}" == "1" &&
      "$classification" != "function_return_contract_mismatch_frontier" ]]; then
  echo "FAIL: generated-stage return contract mismatch gate was not selected" >&2
  exit 9
fi
