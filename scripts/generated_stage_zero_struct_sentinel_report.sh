#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_zero_struct_sentinel_report.sh

Classify the current post-0k-EP generated-stage LLVM validity residual as the
executable red gate for the next zero-struct sentinel slice. This script is a
selector only: it does not prove the root fixed and does not make s2b/s3b green.

Environment:
  CLASSIFIER_LOG=<path>  Reuse an existing generated_stage_finalize_to_s log.
  NORMAL_LL=<path>       Override the normal generated LLVM IR path.
  NORMAL_LOG=<path>      Override the normal run log path.
  KEEP_TMP=1            Keep temporary classifier output when this script runs it.
  REQUIRE_SELECTED=1    Exit nonzero unless the zero-struct sentinel gate is selected.

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
WORK_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-zero-struct.XXXXXX")"
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
    echo "classification=zero_struct_sentinel_classifier_missing_log"
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
raw_dump_classification="$(kv raw_dump_classification "$CLASSIFIER_LOG")"
normal_done_rows="$(kv normal_finalize_to_s_done_rows "$CLASSIFIER_LOG")"
normal_llc_type_mismatch="$(kv normal_llc_type_mismatch "$CLASSIFIER_LOG")"

normal_ll="${NORMAL_LL:-}"
if [[ -z "$normal_ll" && -n "$CLASSIFIER_TMP" ]]; then
  normal_ll="$CLASSIFIER_TMP/normal_out.ll"
fi
normal_log="${NORMAL_LOG:-}"
if [[ -z "$normal_log" ]]; then
  normal_log="$(kv normal_log "$CLASSIFIER_LOG")"
fi
if [[ -z "$normal_log" && -n "$CLASSIFIER_TMP" ]]; then
  normal_log="$CLASSIFIER_TMP/normal.log"
fi

invalid_null_constant_line=""
invalid_null_error_file="missing"
invalid_null_error_line="missing"
invalid_null_error_col="missing"
zero_struct_decl_line=""
zero_struct_decl_line_no="missing"
zero_struct_decl_count=0
zero_struct_section_count=0
zero_struct_error_matches_decl=0

if [[ -n "$normal_log" && -f "$normal_log" ]]; then
  invalid_null_constant_line="$(
    LC_ALL=C grep -a "invalid type for null constant" "$normal_log" 2>/dev/null | tail -1 || true
  )"
  if [[ -n "$invalid_null_constant_line" ]]; then
    invalid_null_error_file="$(
      printf '%s\n' "$invalid_null_constant_line" |
        sed -E "s/^.*llc: ([^:]+):([0-9]+):([0-9]+): error:.*$/\\1/"
    )"
    invalid_null_error_line="$(
      printf '%s\n' "$invalid_null_constant_line" |
        sed -E "s/^.*llc: ([^:]+):([0-9]+):([0-9]+): error:.*$/\\2/"
    )"
    invalid_null_error_col="$(
      printf '%s\n' "$invalid_null_constant_line" |
        sed -E "s/^.*llc: ([^:]+):([0-9]+):([0-9]+): error:.*$/\\3/"
    )"
  fi
fi

if [[ -n "$normal_ll" && -f "$normal_ll" ]]; then
  zero_struct_decl_count="$(
    LC_ALL=C grep -a -c '^@__zero\.Slice\$LUInt8\$R = internal global %Slice\$LUInt8\$R zeroinitializer$' "$normal_ll" 2>/dev/null || true
  )"
  zero_struct_section_count="$(
    LC_ALL=C grep -a -c '^; Zero-filled struct sentinels for cross-block alloca slots$' "$normal_ll" 2>/dev/null || true
  )"
  zero_struct_decl_line="$(
    LC_ALL=C grep -a -n '^@__zero\.Slice\$LUInt8\$R = internal global %Slice\$LUInt8\$R zeroinitializer$' "$normal_ll" 2>/dev/null |
      head -1 || true
  )"
  if [[ -n "$zero_struct_decl_line" ]]; then
    zero_struct_decl_line_no="${zero_struct_decl_line%%:*}"
  fi
  if [[ "$invalid_null_error_line" =~ ^[0-9]+$ &&
        "$zero_struct_decl_line_no" == "$invalid_null_error_line" ]]; then
    zero_struct_error_matches_decl=1
  fi
fi

classification="zero_struct_sentinel_classifier_drift"
selection_status="rejected"
reason="unknown"

if [[ "${classifier_rc:-0}" != "0" && "${classifier_rc:-skipped}" != "skipped" ]]; then
  reason="upstream_classifier_failed"
elif [[ "$upstream_classification" != "post_to_s_frontier" ]]; then
  reason="upstream_classification_not_post_to_s_frontier"
elif [[ "$header_shape" != "i32_12" ]]; then
  reason="string_header_size_scalar_global_not_preserved"
elif [[ "$raw_dump_classification" != "raw_dump_before_to_s_buffer_valid" ]]; then
  reason="raw_dump_not_buffer_valid"
elif [[ "${normal_done_rows:-0}" -le 0 ]]; then
  reason="finalize_to_s_done_not_reached"
elif [[ "${normal_llc_type_mismatch:-missing}" != "0" ]]; then
  reason="function_return_contract_mismatch_still_present"
elif [[ -z "$invalid_null_constant_line" ]]; then
  reason="invalid_null_constant_error_missing"
elif [[ "$zero_struct_decl_count" -ne 1 ]]; then
  reason="zero_slice_uint8_sentinel_declaration_not_unique"
elif [[ "$zero_struct_section_count" -le 0 ]]; then
  reason="zero_struct_sentinel_section_missing"
elif [[ "$zero_struct_error_matches_decl" -ne 1 ]]; then
  reason="llc_error_line_does_not_match_zero_slice_sentinel"
else
  classification="zero_struct_sentinel_invalid_initializer_frontier"
  selection_status="eligible_zero_struct_sentinel_invalid_initializer"
  reason="selected"
fi

echo "# Generated Stage Zero Struct Sentinel Report"
echo "repo=$ROOT_DIR"
echo "classifier_log=$CLASSIFIER_LOG"
echo "classifier_rc=${classifier_rc:-skipped}"
echo "classifier_tmp=${CLASSIFIER_TMP:-missing}"
echo "normal_ll=${normal_ll:-missing}"
echo "normal_log=${normal_log:-missing}"
echo "upstream_classification=$upstream_classification"
echo "normal_string_header_size_global_shape=$header_shape"
if [[ -n "$header_line" ]]; then
  echo "normal_string_header_size_global_line=$header_line"
fi
echo "raw_dump_classification=${raw_dump_classification:-missing}"
echo "normal_finalize_to_s_done_rows=${normal_done_rows:-missing}"
echo "normal_llc_type_mismatch=${normal_llc_type_mismatch:-missing}"
echo "invalid_null_constant_line=${invalid_null_constant_line:-missing}"
echo "invalid_null_error_file=$invalid_null_error_file"
echo "invalid_null_error_line=$invalid_null_error_line"
echo "invalid_null_error_col=$invalid_null_error_col"
echo "zero_struct_section_count=$zero_struct_section_count"
echo "zero_struct_decl_count=$zero_struct_decl_count"
echo "zero_struct_decl_line_no=$zero_struct_decl_line_no"
if [[ -n "$zero_struct_decl_line" ]]; then
  echo "zero_struct_decl_line=${zero_struct_decl_line#*:}"
fi
echo "zero_struct_error_matches_decl=$zero_struct_error_matches_decl"
echo "selection_status=$selection_status"
echo "classification=$classification"
echo "reason=$reason"

if [[ "${REQUIRE_SELECTED:-0}" == "1" &&
      "$classification" != "zero_struct_sentinel_invalid_initializer_frontier" ]]; then
  echo "FAIL: generated-stage zero-struct sentinel gate was not selected" >&2
  exit 9
fi
