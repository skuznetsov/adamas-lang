#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/mir_timed_phase_return_frontier_classifier.sh

Read-only classifier for the post-0k-CL O1 producer boundary.

It reuses scripts/mir_optimization_container_frontier_classifier.sh, keeps the
produced s2 compiler only for this run, then checks whether the current
CopyPropagation affected-block Set is lost at the timed_cp_phase block-return
wrapper rather than in Set(UInt32) construction or Set#includes?.

Environment:
  STAGE1_COMPILER       Stage1 compiler passed to the O1 classifier (default: bin/adamas).
  GENERATED_S2          Optional produced s2 compiler passed through to O1.
  TAIL_LINES            O1/B4 classifier tail lines (default: 80).
  KEEP_TMP=1            Keep temporary artifacts and print their paths.
  REQUIRE_CURRENT_CM=1  Exit nonzero unless the current 0k-CM frontier reproduces.

Current accepted measured-red classification:
  current_0k_cm_timed_cp_phase_block_return_frontier

This script is a classifier only. It is not permission to patch timed_cp_phase,
CopyPropagation, block lowering, backend Set/Hash delegates, or worker/output
behavior.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/mir-timed-phase-return-frontier.XXXXXX")"
O1_TMP=""
B4_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
    [[ -n "$O1_TMP" ]] && echo "o1_kept_tmp=$O1_TMP"
    [[ -n "$B4_TMP" ]] && echo "b4_kept_tmp=$B4_TMP"
  else
    rm -rf "$TMP_DIR"
    [[ -n "$O1_TMP" ]] && rm -rf "$O1_TMP"
    [[ -n "$B4_TMP" ]] && rm -rf "$B4_TMP"
    rm -rf "$ROOT_DIR/tmp/llvm_cache"
  fi
}
trap cleanup EXIT

STAGE1_COMPILER="${STAGE1_COMPILER:-bin/adamas}"
TAIL_LINES="${TAIL_LINES:-80}"
O1_LOG="$TMP_DIR/o1_classifier.log"
CAN_SKIP_LOG="$TMP_DIR/can_skip_entry_lldb.log"
TIMED_DISASM="$TMP_DIR/timed_cp_phase_disasm.log"
APPLY_DISASM="$TMP_DIR/apply_replacements_disasm.log"
COLLECT_DISASM="$TMP_DIR/collect_block_disasm.log"

echo "# MIR Timed Phase Return Frontier Classifier"
echo "repo=$ROOT_DIR"
echo "stage1=$STAGE1_COMPILER"
echo "tail_lines=$TAIL_LINES"
echo "require_current_cm=${REQUIRE_CURRENT_CM:-0}"
echo "note: read-only classifier; no compiler behavior changes"

set +e
if [[ -n "${GENERATED_S2:-}" ]]; then
  KEEP_TMP=1 STAGE1_COMPILER="$STAGE1_COMPILER" GENERATED_S2="$GENERATED_S2" \
    TAIL_LINES="$TAIL_LINES" REQUIRE_CURRENT_O1=1 \
    "$ROOT_DIR/scripts/mir_optimization_container_frontier_classifier.sh" >"$O1_LOG" 2>&1
else
  KEEP_TMP=1 STAGE1_COMPILER="$STAGE1_COMPILER" TAIL_LINES="$TAIL_LINES" \
    REQUIRE_CURRENT_O1=1 \
    "$ROOT_DIR/scripts/mir_optimization_container_frontier_classifier.sh" >"$O1_LOG" 2>&1
fi
o1_rc=$?
set -e

echo "o1_classifier_rc=$o1_rc"

if [[ $o1_rc -ne 0 ]]; then
  echo "o1_classifier_tail:"
  tail -120 "$O1_LOG" || true
  echo "classification=o1_classifier_failed"
  exit 9
fi

o1_classification="$(awk -F= '$1 == "classification" { print $2; exit }' "$O1_LOG")"
O1_TMP="$(awk -F= '$1 == "kept_tmp" { print $2; exit }' "$O1_LOG")"
B4_TMP="$(awk -F= '$1 == "b4_kept_tmp" { print $2; exit }' "$O1_LOG")"
S2="$(awk -F= '$1 == "generated_s2" { print $2; exit }' "$O1_LOG")"
SOURCE="$(awk -F= '$1 == "source" { print $2; exit }' "$O1_LOG")"
bad_container_state="$(awk -F= '$1 == "bad_container_state" { print $2; exit }' "$O1_LOG")"
bad_container_candidate="$(awk -F= '$1 == "bad_container_candidate" { print $2; exit }' "$O1_LOG")"

echo "o1_classification=${o1_classification:-unknown}"
echo "bad_container_state=${bad_container_state:-unknown}"
echo "bad_container_candidate=${bad_container_candidate:-unknown}"
echo "generated_s2=$S2"
echo "source=$SOURCE"

if [[ "${o1_classification:-}" != "current_0k_ck_mir_cp_container_frontier" ]]; then
  echo "classification=o1_not_current_0k_ck_frontier"
  if [[ "${REQUIRE_CURRENT_CM:-0}" == "1" ]]; then
    exit 10
  fi
  exit 0
fi

set +e
lldb --batch \
  -o 'settings set target.env-vars ADAMAS_LLVM_WORKERS=1' \
  -o 'breakpoint set --one-shot true -n Adamas$CCMIR$CCCopyPropagationPass$Hcan_skip_dominators_for_local_replacements$Q$$Hash$LUInt32$C$_UInt32$R_Set$LUInt32$R_Set$LUInt32$R_Hash$LUInt32$C$_UInt32$R_Hash$LUInt32$C$_Int32$R' \
  -o "run $SOURCE -o $TMP_DIR/can_skip_entry_out" \
  -o 'register read x0 x1 x2 x3 x4 x5 x8' \
  -o 'bt 16' \
  -o 'quit' \
  -- "$S2" >"$CAN_SKIP_LOG" 2>&1
can_skip_rc=$?
set -e

set +e
lldb --batch \
  -o 'disassemble -n Adamas$CCMIR$CCCopyPropagationPass$Htimed_cp_phase$$String_block' \
  -o 'quit' \
  -- "$S2" >"$TIMED_DISASM" 2>&1
timed_disasm_rc=$?

lldb --batch \
  -o 'disassemble -n Adamas$CCMIR$CCCopyPropagationPass$Happly_replacements$$Hash$LUInt32$C$_UInt32$R_Bool' \
  -o 'quit' \
  -- "$S2" >"$APPLY_DISASM" 2>&1
apply_disasm_rc=$?

lldb --batch \
  -o 'disassemble -n __crystal_block_proc_1756' \
  -o 'quit' \
  -- "$S2" >"$COLLECT_DISASM" 2>&1
collect_disasm_rc=$?
set -e

echo "can_skip_lldb_rc=$can_skip_rc"
echo "timed_disasm_rc=$timed_disasm_rc"
echo "apply_disasm_rc=$apply_disasm_rc"
echo "collect_disasm_rc=$collect_disasm_rc"

can_skip_entry_hit=0
can_skip_x3_zero=0
timed_calls_block=0
timed_zeroes_after_block=0
timed_enabled_branch_returns_zero=0
apply_collect_uses_timed_phase=0
apply_collect_result_is_nil_void=0
collect_block_builds_set=0
collect_block_returns_set_slot=0

grep -Fq 'stop reason = one-shot breakpoint' "$CAN_SKIP_LOG" && can_skip_entry_hit=1
grep -Eq 'x3 = 0x0+($|[[:space:]])' "$CAN_SKIP_LOG" && can_skip_x3_zero=1

grep -Fq 'blr    x8' "$TIMED_DISASM" && timed_calls_block=1
if awk '/blr[[:space:]]+x8/ { seen = 1; next } seen && /mov[[:space:]]+x8, xzr/ { found = 1 } END { exit(found ? 0 : 1) }' "$TIMED_DISASM"; then
  timed_zeroes_after_block=1
fi
if awk '/tbz.*76/ { seen = 1; next } seen && /mov[[:space:]]+x8, xzr/ { found = 1 } END { exit(found ? 0 : 1) }' "$TIMED_DISASM"; then
  timed_enabled_branch_returns_zero=1
fi

grep -Fq '__crystal_block_proc_1756' "$APPLY_DISASM" && \
  grep -Fq 'Adamas$CCMIR$CCCopyPropagationPass$Htimed_cp_phase$$String_block' "$APPLY_DISASM" && \
  apply_collect_uses_timed_phase=1
grep -Fq 'Nil$_$OR$_Void$Hempty$Q' "$APPLY_DISASM" && apply_collect_result_is_nil_void=1

grep -Fq 'Set$LUInt32$R$Dnew' "$COLLECT_DISASM" && \
  grep -Fq 'Set$LUInt32$R$H$SHL$$UInt32' "$COLLECT_DISASM" && \
  collect_block_builds_set=1
if grep -Fq 'ldr    x0, [sp, #0x10]' "$COLLECT_DISASM" && grep -Fq 'ret' "$COLLECT_DISASM"; then
  collect_block_returns_set_slot=1
fi

classification="timed_phase_return_unmatched"
if [[ $can_skip_entry_hit -eq 1 &&
      $can_skip_x3_zero -eq 1 &&
      $timed_calls_block -eq 1 &&
      $timed_zeroes_after_block -eq 1 &&
      $timed_enabled_branch_returns_zero -eq 1 &&
      $apply_collect_uses_timed_phase -eq 1 &&
      $apply_collect_result_is_nil_void -eq 1 &&
      $collect_block_builds_set -eq 1 &&
      $collect_block_returns_set_slot -eq 1 ]]; then
  classification="current_0k_cm_timed_cp_phase_block_return_frontier"
fi

echo "can_skip_entry_hit=$can_skip_entry_hit"
echo "can_skip_affected_block_ids_x3_zero=$can_skip_x3_zero"
echo "timed_calls_block=$timed_calls_block"
echo "timed_zeroes_after_block=$timed_zeroes_after_block"
echo "timed_enabled_branch_returns_zero=$timed_enabled_branch_returns_zero"
echo "apply_collect_uses_timed_phase=$apply_collect_uses_timed_phase"
echo "apply_collect_result_is_nil_void=$apply_collect_result_is_nil_void"
echo "collect_block_builds_set=$collect_block_builds_set"
echo "collect_block_returns_set_slot=$collect_block_returns_set_slot"
echo "can_skip_log=$CAN_SKIP_LOG"
echo "timed_disasm=$TIMED_DISASM"
echo "apply_disasm=$APPLY_DISASM"
echo "collect_disasm=$COLLECT_DISASM"
echo "classification=$classification"

if [[ "$classification" != "current_0k_cm_timed_cp_phase_block_return_frontier" ]]; then
  echo "can_skip_tail:"
  tail -80 "$CAN_SKIP_LOG" || true
  echo "timed_disasm_excerpt:"
  sed -n '1,140p' "$TIMED_DISASM" || true
  echo "apply_disasm_matches:"
  rg -n 'timed_cp_phase|__crystal_block_proc_1756|Nil\\$_\\$OR\\$_Void\\$Hempty\\$Q' "$APPLY_DISASM" || true
  echo "collect_disasm_matches:"
  rg -n 'Set\\$LUInt32\\$R\\$Dnew|Set\\$LUInt32\\$R\\$H\\$SHL|ldr[[:space:]]+x0, \\[sp, #0x10\\]|ret' "$COLLECT_DISASM" || true
fi

if [[ "${REQUIRE_CURRENT_CM:-0}" == "1" &&
      "$classification" != "current_0k_cm_timed_cp_phase_block_return_frontier" ]]; then
  exit 12
fi

exit 0
