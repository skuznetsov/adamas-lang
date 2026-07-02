#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/mir_optimization_container_frontier_classifier.sh

Read-only classifier for Slice 0k-CK / falsifier O1.

It reuses the generated-stage B4 classifier, keeps the produced s2 compiler
only for this run, then runs the workers=1 path under lldb and classifies the
current MIR optimization / compiler-runtime-container crash.

Environment:
  STAGE1_COMPILER       Stage1 compiler to pass to the B4 classifier (default: bin/adamas).
  GENERATED_S2          Optional produced s2 compiler to pass to the B4 classifier.
  TAIL_LINES            B4 classifier tail lines (default: 80).
  KEEP_TMP=1            Keep all temporary artifacts and print their paths.
  REQUIRE_CURRENT_O1=1  Exit nonzero unless the current 0k-CK O1 frontier reproduces.

Current accepted measured-red classification:
  current_0k_ck_mir_cp_container_frontier

This script is a classifier only. It is not permission to patch CopyPropagation,
backend Set/Hash delegates, worker/resource/output/tail behavior, or broad
namespace/container rendering.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$ROOT_DIR/tmp"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/mir-opt-container-frontier.XXXXXX")"
B4_TMP=""

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
    [[ -n "$B4_TMP" ]] && echo "b4_kept_tmp=$B4_TMP"
  else
    rm -rf "$TMP_DIR"
    [[ -n "$B4_TMP" ]] && rm -rf "$B4_TMP"
    rm -rf "$ROOT_DIR/tmp/llvm_cache"
  fi
}
trap cleanup EXIT

STAGE1_COMPILER="${STAGE1_COMPILER:-bin/adamas}"
TAIL_LINES="${TAIL_LINES:-80}"
B4_LOG="$TMP_DIR/b4_classifier.log"
LLDB_LOG="$TMP_DIR/workers1_lldb.log"

echo "# MIR Optimization Container Frontier Classifier"
echo "repo=$ROOT_DIR"
echo "stage1=$STAGE1_COMPILER"
echo "tail_lines=$TAIL_LINES"
echo "require_current_o1=${REQUIRE_CURRENT_O1:-0}"
echo "note: read-only classifier; no compiler behavior changes"

set +e
if [[ -n "${GENERATED_S2:-}" ]]; then
  KEEP_TMP=1 STAGE1_COMPILER="$STAGE1_COMPILER" GENERATED_S2="$GENERATED_S2" \
    TAIL_LINES="$TAIL_LINES" \
    "$ROOT_DIR/scripts/generated_stage_llvm_entry_classifier.sh" >"$B4_LOG" 2>&1
else
  KEEP_TMP=1 STAGE1_COMPILER="$STAGE1_COMPILER" TAIL_LINES="$TAIL_LINES" \
    "$ROOT_DIR/scripts/generated_stage_llvm_entry_classifier.sh" >"$B4_LOG" 2>&1
fi
b4_rc=$?
set -e

echo "b4_classifier_rc=$b4_rc"

if [[ $b4_rc -ne 0 ]]; then
  echo "b4_classifier_tail:"
  tail -100 "$B4_LOG" || true
  echo "classification=b4_classifier_failed"
  exit 9
fi

b4_classification="$(awk -F= '$1 == "classification" { print $2; exit }' "$B4_LOG")"
B4_TMP="$(awk -F= '$1 == "kept_tmp" { print $2; exit }' "$B4_LOG")"
S2="$(awk -F= '$1 == "generated_s2" { print $2; exit }' "$B4_LOG")"
SOURCE="$(awk -F= '$1 == "source" { print $2; exit }' "$B4_LOG")"
workers1_exit139="$(awk -F= '$1 == "workers1_exit139" { print $2; exit }' "$B4_LOG")"
workers1_after_lower_main="$(awk -F= '$1 == "workers1_after_lower_main" { print $2; exit }' "$B4_LOG")"

echo "b4_classification=${b4_classification:-unknown}"
echo "workers1_after_lower_main=${workers1_after_lower_main:-unknown}"
echo "workers1_exit139=${workers1_exit139:-unknown}"
echo "generated_s2=$S2"
echo "source=$SOURCE"

if [[ "${b4_classification:-}" != "current_0k_bn_frontier" ]]; then
  echo "classification=b4_not_current_0k_bn_frontier"
  if [[ "${REQUIRE_CURRENT_O1:-0}" == "1" ]]; then
    exit 10
  fi
  exit 0
fi

if [[ "${workers1_exit139:-0}" != "1" || "${workers1_after_lower_main:-0}" != "1" ]]; then
  echo "classification=workers1_not_crashing_after_lower_main"
  if [[ "${REQUIRE_CURRENT_O1:-0}" == "1" ]]; then
    exit 11
  fi
  exit 0
fi

set +e
lldb --batch \
  -o 'settings set target.env-vars ADAMAS_LLVM_WORKERS=1' \
  -o "run $SOURCE -o $TMP_DIR/lldb_out" \
  -k 'disassemble --frame' \
  -k 'register read x0 x1 x2 x8' \
  -k 'bt 80' \
  -k 'quit' \
  -- "$S2" >"$LLDB_LOG" 2>&1
lldb_rc=$?
set -e

echo "lldb_rc=$lldb_rc"

has_set_uint32_includes=0
has_copyprop_affected=0
has_copyprop_can_skip=0
has_optimize_with_potential=0
x0_zero=0
x8_zero=0
set_load_from_x8=0
affected_includes_count=0

grep -Fq 'Set$LUInt32$R$Hincludes$Q$$UInt32' "$LLDB_LOG" && has_set_uint32_includes=1
grep -Fq 'CopyPropagationPass$Haffected_blocks_use_only_local_replacements$Q' "$LLDB_LOG" && has_copyprop_affected=1
grep -Fq 'CopyPropagationPass$Hcan_skip_dominators_for_local_replacements$Q' "$LLDB_LOG" && has_copyprop_can_skip=1
grep -Fq 'Function$Hoptimize_with_potential' "$LLDB_LOG" && has_optimize_with_potential=1
grep -Eq 'x0 = 0x0+($|[[:space:]])' "$LLDB_LOG" && x0_zero=1
grep -Eq 'x8 = 0x0+($|[[:space:]])' "$LLDB_LOG" && x8_zero=1
grep -Eq 'ldr[[:space:]]+x0, \[x8\]' "$LLDB_LOG" && set_load_from_x8=1

affected_includes_count="$(
  awk '
    /private def affected_blocks_use_only_local_replacements\?/ { in_method = 1; next }
    in_method && /private def block_uses_only_local_replacements\?/ { in_method = 0 }
    in_method && /includes\?\(/ { count++ }
    END { print count + 0 }
  ' "$ROOT_DIR/src/compiler/mir/optimizations.cr"
)"

bad_container_state="unknown"
bad_container_candidate="unknown"
classification="o1_stack_unmatched"

if [[ $has_set_uint32_includes -eq 1 &&
      $has_copyprop_affected -eq 1 &&
      $has_copyprop_can_skip -eq 1 &&
      $has_optimize_with_potential -eq 1 ]]; then
  if [[ $x8_zero -eq 1 && $set_load_from_x8 -eq 1 ]]; then
    bad_container_state="set_receiver_base_register_null"
  elif [[ $x0_zero -eq 1 ]]; then
    bad_container_state="set_or_hash_register_null"
  else
    bad_container_state="set_hash_or_storage_unknown"
  fi

  if [[ "$affected_includes_count" == "1" ]]; then
    bad_container_candidate="affected_block_ids"
  else
    bad_container_candidate="ambiguous_copyprop_set"
  fi

  classification="current_0k_ck_mir_cp_container_frontier"
fi

echo "has_set_uint32_includes=$has_set_uint32_includes"
echo "has_copyprop_affected=$has_copyprop_affected"
echo "has_copyprop_can_skip=$has_copyprop_can_skip"
echo "has_optimize_with_potential=$has_optimize_with_potential"
echo "register_x0_zero=$x0_zero"
echo "register_x8_zero=$x8_zero"
echo "set_load_from_x8=$set_load_from_x8"
echo "affected_method_includes_count=$affected_includes_count"
echo "bad_container_state=$bad_container_state"
echo "bad_container_candidate=$bad_container_candidate"
echo "lldb_log=$LLDB_LOG"
echo "classification=$classification"

if [[ "$classification" != "current_0k_ck_mir_cp_container_frontier" ]]; then
  echo "lldb_tail:"
  tail -120 "$LLDB_LOG" || true
fi

if [[ "${REQUIRE_CURRENT_O1:-0}" == "1" &&
      "$classification" != "current_0k_ck_mir_cp_container_frontier" ]]; then
  exit 12
fi

exit 0
