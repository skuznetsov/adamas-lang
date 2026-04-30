#!/usr/bin/env bash
# Guard backend-owned Proc#call HIR calls.
#
# Proc#call must stay visible as a HIR Call for MIR heap-proc lowering, but it
# must not be demand-driven as a source-level HIR function by lower_missing.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_proc_call_boundary_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/proc_call_boundary.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/run.log"

cat >"$SRC" <<'CR'
p = ->(x : Int32) { x + 1 }
p.call(41)

q = -> { 7 }
q.call
CR

DEBUG_MISSING_SUMMARY=1 \
DEBUG_MISSING_TOP=30 \
CRYSTAL_V2_STOP_AFTER_HIR=1 \
CRYSTAL_V2_PHASE_STATS=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
    "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

HIR="$OUT.hir"
if [[ ! -s "$HIR" ]]; then
  echo "p2 proc call backend boundary regression: missing HIR artifact" >&2
  cat "$LOG" >&2
  exit 1
fi

if ! grep -q "Proc#call" "$HIR"; then
  echo "p2 proc call backend boundary regression: Proc#call missing from HIR" >&2
  cat "$HIR" >&2
  exit 1
fi

if grep -q "Proc#call" "$LOG"; then
  echo "p2 proc call backend boundary regression: Proc#call was treated as missing source demand" >&2
  grep "Proc#call" "$LOG" >&2
  exit 1
fi

echo "p2_proc_call_backend_boundary_no_prelude_ok"
