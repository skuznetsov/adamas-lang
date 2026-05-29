#!/usr/bin/env bash
# Tier-1 guard for opt-in LLVM backend reachability pruning.
#
# The default backend path still emits all MIR functions. This guard only proves
# that CRYSTAL_V2_LLVM_REACHABILITY=1 reaches the backend RTA path on a small
# no-prelude corpus and still emits LLVM IR.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SRC="$ROOT_DIR/regression_tests/bootstrap_semantic_corpus.cr"

TIMEOUT_SEC="${P2_LLVM_REACH_TIMEOUT_SEC:-60}"
MEM_MB="${P2_LLVM_REACH_MEM_MB:-2048}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_llvm_reachability_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUT="$TMP_DIR/corpus"
LOG="$TMP_DIR/run_safe.log"

CRYSTAL_V2_LLVM_REACHABILITY=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
    "$SRC" --no-prelude --emit llvm-ir --no-link --progress -o "$OUT" >"$LOG" 2>&1

if ! grep -Eq 'RTA kept:|\[REACHABILITY\]' "$LOG"; then
  echo "p2 llvm reachability regression: backend RTA path did not run" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

if [[ ! -s "$OUT.ll" ]]; then
  echo "p2 llvm reachability regression: missing LLVM artifact" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

if grep -q '\[KILL\]' "$LOG"; then
  echo "p2 llvm reachability regression: run_safe killed compiler" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

summary="$(grep -E 'RTA kept:|emitting [0-9]+ functions' "$LOG" | tail -1 | sed -E 's/^ *\\[LLVM\\] //')"
echo "p2_llvm_reachability_no_prelude_ok ${summary}"
