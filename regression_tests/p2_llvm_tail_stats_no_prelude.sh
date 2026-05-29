#!/usr/bin/env bash
# Tier-1 guard for opt-in LLVM backend tail-generation diagnostics.
#
# The diagnostic is trace-gated: CRYSTAL_V2_LLVM_TAIL_STATS selects the timing
# probes, while CRYSTAL_V2_TRACE_STDERR makes bootstrap_trace_puts visible.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SRC="$ROOT_DIR/regression_tests/bootstrap_semantic_corpus.cr"

TIMEOUT_SEC="${P2_LLVM_TAIL_TIMEOUT_SEC:-60}"
MEM_MB="${P2_LLVM_TAIL_MEM_MB:-2048}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_llvm_tail_stats_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUT="$TMP_DIR/corpus"
LOG="$TMP_DIR/run_safe.log"

CRYSTAL_V2_TRACE_STDERR=1 \
CRYSTAL_V2_LLVM_REACHABILITY=1 \
CRYSTAL_V2_LLVM_TAIL_STATS=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
    "$SRC" --no-prelude --emit llvm-ir --no-link --progress -o "$OUT" >"$LOG" 2>&1

for phase in string_constants undefined_externs type_name_table finalize_enter; do
  if ! grep -q "\\[LLVM_TAIL_GEN\\] phase=${phase}" "$LOG"; then
    echo "p2 llvm tail stats regression: missing phase ${phase}" >&2
    tail -160 "$LOG" >&2
    exit 1
  fi
done

if [[ ! -s "$OUT.ll" ]]; then
  echo "p2 llvm tail stats regression: missing LLVM artifact" >&2
  tail -160 "$LOG" >&2
  exit 1
fi

if grep -q '\[KILL\]' "$LOG"; then
  echo "p2 llvm tail stats regression: run_safe killed compiler" >&2
  tail -160 "$LOG" >&2
  exit 1
fi

summary="$(grep '\[LLVM_TAIL_GEN\] phase=type_name_table' "$LOG" | tail -1 | sed -E 's/^.*\[LLVM_TAIL_GEN\] //')"
echo "p2_llvm_tail_stats_no_prelude_ok ${summary}"
