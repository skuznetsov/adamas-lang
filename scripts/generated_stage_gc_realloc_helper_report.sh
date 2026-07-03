#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/generated_stage_gc_realloc_helper_report.sh

Classify the current post-0k-ER generated-stage LLVM validity residual as the
runtime-helper declaration availability frontier for @__adamas_gc_aware_realloc.
This script is a selector only: it does not prove the root fixed and does not
make s2b/s3b green.

Environment:
  CLASSIFIER_LOG=<path>  Reuse an existing generated_stage_finalize_to_s log.
  NORMAL_LL=<path>       Override the normal generated LLVM IR path.
  NORMAL_LOG=<path>      Override the normal run log path.
  KEEP_TMP=1            Keep temporary classifier output when this script runs it.
  REQUIRE_SELECTED=1    Exit nonzero unless the GC-aware realloc helper gate is selected.

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
WORK_DIR="$(mktemp -d "$ROOT_DIR/tmp/generated-stage-gc-realloc-helper.XXXXXX")"
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
    echo "classification=gc_realloc_helper_classifier_missing_log"
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

undefined_helper_line=""
undefined_helper_error_file="missing"
undefined_helper_error_line="missing"
undefined_helper_error_col="missing"
invalid_null_constant_line=""

if [[ -n "$normal_log" && -f "$normal_log" ]]; then
  undefined_helper_line="$(
    LC_ALL=C grep -a "undefined value '@__adamas_gc_aware_realloc'" "$normal_log" 2>/dev/null |
      tail -1 || true
  )"
  if [[ -n "$undefined_helper_line" ]]; then
    undefined_helper_error_file="$(
      printf '%s\n' "$undefined_helper_line" |
        sed -E "s/^.*llc: ([^:]+):([0-9]+):([0-9]+): error:.*$/\\1/"
    )"
    undefined_helper_error_line="$(
      printf '%s\n' "$undefined_helper_line" |
        sed -E "s/^.*llc: ([^:]+):([0-9]+):([0-9]+): error:.*$/\\2/"
    )"
    undefined_helper_error_col="$(
      printf '%s\n' "$undefined_helper_line" |
        sed -E "s/^.*llc: ([^:]+):([0-9]+):([0-9]+): error:.*$/\\3/"
    )"
  fi
  invalid_null_constant_line="$(
    LC_ALL=C grep -a "invalid type for null constant" "$normal_log" 2>/dev/null |
      tail -1 || true
  )"
fi

helper_call_count=0
helper_define_count=0
helper_declare_count=0
helper_error_matches_call=0
gc_realloc_decl_count=0
gc_base_decl_count=0
slice_raw_alloca_count=0
slice_named_alloca_count=0
zero_slice_raw_decl_count=0
zero_slice_named_decl_count=0

if [[ -n "$normal_ll" && -f "$normal_ll" ]]; then
  helper_call_count="$(
    LC_ALL=C grep -a -c 'call ptr @__adamas_gc_aware_realloc(' "$normal_ll" 2>/dev/null || true
  )"
  helper_define_count="$(
    LC_ALL=C grep -a -c '^define ptr @__adamas_gc_aware_realloc(' "$normal_ll" 2>/dev/null || true
  )"
  helper_declare_count="$(
    LC_ALL=C grep -a -c '^declare ptr @__adamas_gc_aware_realloc(' "$normal_ll" 2>/dev/null || true
  )"
  gc_realloc_decl_count="$(
    LC_ALL=C grep -a -c '^declare ptr @GC_realloc(ptr, i64)' "$normal_ll" 2>/dev/null || true
  )"
  gc_base_decl_count="$(
    LC_ALL=C grep -a -c '^declare ptr @GC_base(ptr)' "$normal_ll" 2>/dev/null || true
  )"
  slice_raw_alloca_count="$(
    LC_ALL=C grep -a -c '%r2 = alloca \[16 x i8\], align 8' "$normal_ll" 2>/dev/null || true
  )"
  slice_named_alloca_count="$(
    LC_ALL=C grep -a -c '%r2 = alloca %Slice\$LUInt8\$R' "$normal_ll" 2>/dev/null || true
  )"
  zero_slice_raw_decl_count="$(
    LC_ALL=C grep -a -c '^@__zero\.Slice\$LUInt8\$R = internal global \[16 x i8\] zeroinitializer, align 8$' "$normal_ll" 2>/dev/null || true
  )"
  zero_slice_named_decl_count="$(
    LC_ALL=C grep -a -c '^@__zero\.Slice\$LUInt8\$R = internal global %Slice\$LUInt8\$R zeroinitializer$' "$normal_ll" 2>/dev/null || true
  )"
  if [[ "$undefined_helper_error_line" =~ ^[0-9]+$ ]]; then
    error_ir_line="$(
      sed -n "${undefined_helper_error_line}p" "$normal_ll" 2>/dev/null || true
    )"
    if [[ "$error_ir_line" == *"call ptr @__adamas_gc_aware_realloc("* ]]; then
      helper_error_matches_call=1
    fi
  fi
fi

classification="gc_realloc_helper_classifier_drift"
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
elif [[ -n "$invalid_null_constant_line" ]]; then
  reason="zero_struct_invalid_null_constant_still_present"
elif [[ "$slice_named_alloca_count" -ne 0 || "$zero_slice_named_decl_count" -ne 0 ]]; then
  reason="slice_named_aggregate_storage_still_present"
elif [[ "$slice_raw_alloca_count" -le 0 || "$zero_slice_raw_decl_count" -le 0 ]]; then
  reason="raw_slice_storage_shape_not_preserved"
elif [[ -z "$undefined_helper_line" ]]; then
  reason="undefined_gc_realloc_helper_error_missing"
elif [[ "$helper_call_count" -le 0 ]]; then
  reason="gc_realloc_helper_call_missing"
elif [[ "$helper_define_count" -ne 0 || "$helper_declare_count" -ne 0 ]]; then
  reason="gc_realloc_helper_declaration_or_definition_present"
elif [[ "$helper_error_matches_call" -ne 1 ]]; then
  reason="llc_error_line_does_not_match_gc_realloc_call"
else
  classification="runtime_helper_gc_realloc_missing_declaration_frontier"
  selection_status="eligible_gc_realloc_helper_missing_declaration"
  reason="selected"
fi

echo "# Generated Stage GC Realloc Helper Report"
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
echo "slice_raw_alloca_count=$slice_raw_alloca_count"
echo "slice_named_alloca_count=$slice_named_alloca_count"
echo "zero_slice_raw_decl_count=$zero_slice_raw_decl_count"
echo "zero_slice_named_decl_count=$zero_slice_named_decl_count"
echo "undefined_gc_realloc_helper_line=${undefined_helper_line:-missing}"
echo "undefined_gc_realloc_error_file=$undefined_helper_error_file"
echo "undefined_gc_realloc_error_line=$undefined_helper_error_line"
echo "undefined_gc_realloc_error_col=$undefined_helper_error_col"
echo "gc_realloc_helper_call_count=$helper_call_count"
echo "gc_realloc_helper_define_count=$helper_define_count"
echo "gc_realloc_helper_declare_count=$helper_declare_count"
echo "gc_realloc_decl_count=$gc_realloc_decl_count"
echo "gc_base_decl_count=$gc_base_decl_count"
echo "gc_realloc_helper_error_matches_call=$helper_error_matches_call"
echo "selection_status=$selection_status"
echo "classification=$classification"
echo "reason=$reason"

if [[ "${REQUIRE_SELECTED:-0}" == "1" &&
      "$classification" != "runtime_helper_gc_realloc_missing_declaration_frontier" ]]; then
  echo "FAIL: generated-stage GC realloc helper gate was not selected" >&2
  exit 9
fi
