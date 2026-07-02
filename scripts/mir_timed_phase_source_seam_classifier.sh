#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/mir_timed_phase_source_seam_classifier.sh

Read-only classifier for the post-0k-CM timed_cp_phase source seam.

It emits a HIR dump for src/adamas.cr and checks whether the
CopyPropagationPass#timed_cp_phase(String, &) wrapper is already typed as
Nil|Void / yield:Void in HIR while the apply_collect_affected_blocks block
still constructs and returns Set(UInt32). This distinguishes HIR
block-return/call-return inference from later MIR or LLVM backend return
handling before any behavior patch.

Environment:
  STAGE1_COMPILER          Compiler used for the HIR dump (default: bin/adamas).
  RUN_CURRENT_CM=1         Also run the 0k-CM produced-stage classifier first.
  TAIL_LINES               Passed to the 0k-CM classifier when RUN_CURRENT_CM=1.
  KEEP_TMP=1               Keep temporary artifacts and print their paths.
  REQUIRE_CURRENT_CN=1     Exit nonzero unless the current 0k-CN seam reproduces.

Current accepted measured-red classification:
  current_0k_cn_hir_timed_phase_source_seam

This script is a classifier only. It is not permission to patch timed_cp_phase,
CopyPropagation, block lowering, backend block-return rescue, Set/Hash
delegates, workers, output, or BlockOwner.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/mir-timed-source-seam.XXXXXX")"
CM_TMP=""
CM_B4_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
    [[ -n "$CM_TMP" ]] && echo "cm_kept_tmp=$CM_TMP"
    [[ -n "$CM_B4_TMP" ]] && echo "cm_b4_kept_tmp=$CM_B4_TMP"
  else
    rm -rf "$TMP_DIR"
    [[ -n "$CM_TMP" ]] && rm -rf "$CM_TMP"
    [[ -n "$CM_B4_TMP" ]] && rm -rf "$CM_B4_TMP"
    rm -rf "$ROOT_DIR/tmp/llvm_cache"
  fi
}
trap cleanup EXIT

STAGE1_COMPILER="${STAGE1_COMPILER:-bin/adamas}"
TAIL_LINES="${TAIL_LINES:-80}"
CM_LOG="$TMP_DIR/cm_classifier.log"
HIR_OUT="$TMP_DIR/hir.out"
HIR_ERR="$TMP_DIR/hir.err"
HIR_BASE="$TMP_DIR/adamas_hir"
HIR_FILE="$HIR_BASE.hir"

echo "# MIR Timed Phase Source Seam Classifier"
echo "repo=$ROOT_DIR"
echo "stage1=$STAGE1_COMPILER"
echo "run_current_cm=${RUN_CURRENT_CM:-0}"
echo "require_current_cn=${REQUIRE_CURRENT_CN:-0}"
echo "note: read-only classifier; no compiler behavior changes"

cm_classification="skipped"
if [[ "${RUN_CURRENT_CM:-0}" == "1" ]]; then
  set +e
  KEEP_TMP=1 STAGE1_COMPILER="$STAGE1_COMPILER" TAIL_LINES="$TAIL_LINES" \
    REQUIRE_CURRENT_CM=1 \
    "$ROOT_DIR/scripts/mir_timed_phase_return_frontier_classifier.sh" >"$CM_LOG" 2>&1
  cm_rc=$?
  set -e

  echo "cm_classifier_rc=$cm_rc"
  if [[ $cm_rc -ne 0 ]]; then
    echo "cm_classifier_tail:"
    tail -120 "$CM_LOG" || true
    echo "classification=cm_classifier_failed"
    exit 9
  fi

  cm_classification="$(awk -F= '$1 == "classification" { print $2; exit }' "$CM_LOG")"
  CM_TMP="$(awk -F= '$1 == "kept_tmp" { print $2; exit }' "$CM_LOG")"
  CM_B4_TMP="$(awk -F= '$1 == "b4_kept_tmp" { print $2; exit }' "$CM_LOG")"
fi
echo "cm_classification=$cm_classification"

set +e
ADAMAS_STOP_AFTER_HIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$STAGE1_COMPILER" 300 4096 \
  "$ROOT_DIR/src/adamas.cr" --emit hir --no-link -o "$HIR_BASE" \
  >"$HIR_OUT" 2>"$HIR_ERR"
hir_rc=$?
set -e

echo "hir_dump_rc=$hir_rc"
if [[ $hir_rc -ne 0 || ! -f "$HIR_FILE" ]]; then
  echo "classification=hir_dump_failed"
  echo "hir_err_tail:"
  tail -120 "$HIR_ERR" || true
  exit 10
fi

timed_func_line="$(rg -n -F 'func @Adamas::MIR::CopyPropagationPass#timed_cp_phase$String_block(' "$HIR_FILE" | head -1 || true)"
collect_proc_line="$(rg -n -F 'func @__crystal_block_proc_1756()' "$HIR_FILE" | head -1 || true)"
apply_literal_line_no="$(rg -n 'literal "apply_collect_affected_blocks"' "$HIR_FILE" | head -1 | cut -d: -f1 || true)"

timed_return_type=""
collect_proc_return_type=""
if [[ -n "$timed_func_line" ]]; then
  timed_return_type="$(printf '%s\n' "$timed_func_line" | sed -E 's/.* -> ([0-9]+) \{.*/\1/')"
fi
if [[ -n "$collect_proc_line" ]]; then
  collect_proc_return_type="$(printf '%s\n' "$collect_proc_line" | sed -E 's/.* -> ([0-9]+) \{.*/\1/')"
fi

wrapper_yield_void=0
wrapper_wraps_void_to_return=0
wrapper_returns_phi=0
if [[ -n "$timed_func_line" ]]; then
  timed_line_no="$(printf '%s\n' "$timed_func_line" | cut -d: -f1)"
  timed_excerpt="$TMP_DIR/timed_wrapper.hir"
  sed -n "${timed_line_no},$((timed_line_no + 40))p" "$HIR_FILE" >"$timed_excerpt"
  grep -Eq '= yield : 0$' "$timed_excerpt" && wrapper_yield_void=1
  if [[ -n "$timed_return_type" ]] && grep -Eq "union_wrap %[0-9]+ as variant 0 : ${timed_return_type}$" "$timed_excerpt"; then
    wrapper_wraps_void_to_return=1
  fi
  grep -Eq 'return %[0-9]+' "$timed_excerpt" && wrapper_returns_phi=1
fi

collect_block_builds_set=0
collect_block_proc_returns_set=0
apply_collect_call_type=""
affected_local_type=""
apply_collect_uses_timed=0
apply_collect_result_nil_void=0
if [[ -n "$apply_literal_line_no" ]]; then
  apply_excerpt="$TMP_DIR/apply_collect.hir"
  sed -n "${apply_literal_line_no},$((apply_literal_line_no + 90))p" "$HIR_FILE" >"$apply_excerpt"
  grep -Fq 'call ::Set(UInt32).new()' "$apply_excerpt" && collect_block_builds_set=1
  if [[ -n "$collect_proc_return_type" ]] && grep -Eq "call ::Set\\(UInt32\\)\\.new\\(\\) : ${collect_proc_return_type}$" "$apply_excerpt"; then
    collect_block_proc_returns_set=1
  fi
  call_line="$(grep -F 'CopyPropagationPass#timed_cp_phase$String_block' "$apply_excerpt" | head -1 || true)"
  if [[ -n "$call_line" ]]; then
    apply_collect_uses_timed=1
    apply_collect_call_type="$(printf '%s\n' "$call_line" | sed -E 's/.* : ([0-9]+) with_block.*/\1/')"
  fi
  local_line="$(grep -E 'local "affected_block_ids"' "$apply_excerpt" | head -1 || true)"
  if [[ -n "$local_line" ]]; then
    affected_local_type="$(printf '%s\n' "$local_line" | sed -E 's/.* : ([0-9]+) .*/\1/')"
  fi
  grep -Fq 'Nil | Void#empty?' "$apply_excerpt" && apply_collect_result_nil_void=1
fi

call_matches_wrapper_return=0
affected_local_matches_call=0
call_differs_from_collect_proc=0
if [[ -n "$apply_collect_call_type" && -n "$timed_return_type" && "$apply_collect_call_type" == "$timed_return_type" ]]; then
  call_matches_wrapper_return=1
fi
if [[ -n "$apply_collect_call_type" && -n "$affected_local_type" && "$apply_collect_call_type" == "$affected_local_type" ]]; then
  affected_local_matches_call=1
fi
if [[ -n "$apply_collect_call_type" && -n "$collect_proc_return_type" && "$apply_collect_call_type" != "$collect_proc_return_type" ]]; then
  call_differs_from_collect_proc=1
fi

classification="timed_phase_source_seam_unmatched"
if [[ -n "$timed_func_line" &&
      -n "$collect_proc_line" &&
      $wrapper_yield_void -eq 1 &&
      $wrapper_wraps_void_to_return -eq 1 &&
      $wrapper_returns_phi -eq 1 &&
      $collect_block_builds_set -eq 1 &&
      $collect_block_proc_returns_set -eq 1 &&
      $apply_collect_uses_timed -eq 1 &&
      $apply_collect_result_nil_void -eq 1 &&
      $call_matches_wrapper_return -eq 1 &&
      $affected_local_matches_call -eq 1 &&
      $call_differs_from_collect_proc -eq 1 ]]; then
  classification="current_0k_cn_hir_timed_phase_source_seam"
fi

echo "timed_wrapper_present=$([[ -n "$timed_func_line" ]] && echo 1 || echo 0)"
echo "timed_wrapper_return_type=${timed_return_type:-missing}"
echo "wrapper_yield_void=$wrapper_yield_void"
echo "wrapper_wraps_void_to_return=$wrapper_wraps_void_to_return"
echo "wrapper_returns_phi=$wrapper_returns_phi"
echo "collect_proc_present=$([[ -n "$collect_proc_line" ]] && echo 1 || echo 0)"
echo "collect_proc_return_type=${collect_proc_return_type:-missing}"
echo "collect_block_builds_set=$collect_block_builds_set"
echo "collect_block_proc_returns_set=$collect_block_proc_returns_set"
echo "apply_collect_uses_timed_phase=$apply_collect_uses_timed"
echo "apply_collect_call_type=${apply_collect_call_type:-missing}"
echo "affected_block_ids_local_type=${affected_local_type:-missing}"
echo "apply_collect_result_nil_void=$apply_collect_result_nil_void"
echo "call_matches_wrapper_return=$call_matches_wrapper_return"
echo "affected_local_matches_call=$affected_local_matches_call"
echo "call_differs_from_collect_proc=$call_differs_from_collect_proc"
echo "hir_file=$HIR_FILE"
echo "classification=$classification"

if [[ "$classification" != "current_0k_cn_hir_timed_phase_source_seam" ]]; then
  echo "timed_wrapper_excerpt:"
  [[ -f "$TMP_DIR/timed_wrapper.hir" ]] && sed -n '1,80p' "$TMP_DIR/timed_wrapper.hir" || true
  echo "apply_collect_excerpt:"
  [[ -f "$TMP_DIR/apply_collect.hir" ]] && sed -n '1,120p' "$TMP_DIR/apply_collect.hir" || true
fi

if [[ "${REQUIRE_CURRENT_CN:-0}" == "1" &&
      "$classification" != "current_0k_cn_hir_timed_phase_source_seam" ]]; then
  exit 12
fi

exit 0
