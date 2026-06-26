#!/usr/bin/env bash
# Regression: produced s2b must materialize the nilable-name wrapper for
# AstToHir#yield_return_function_for_block_call? instead of emitting an
# undefined-extern abort stub for the full-prelude lowering path.
#
# This is a focused frontier guard, not a full s2b readiness test: later
# compiler phases may still fail while this materialization contract stays
# fixed.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_yield_return_block_call.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/puts42.cr"
OUT="$TMP_DIR/puts42"
LOG="$TMP_DIR/compile.log"

cat > "$SRC" <<'CR'
puts 42
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 "$SRC" -o "$OUT" >"$LOG" 2>&1
status=$?
set -e

if grep -Fq "error: Unreachable" "$LOG"; then
  echo "FAIL: did not reach the yield-return block-call materialization frontier" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

if grep -Fq "STUB CALLED: Adamas\$CCHIR\$CCAstToHir\$Hyield_return_function_for_block_call" "$LOG"; then
  echo "FAIL: yield_return_function_for_block_call? nilable wrapper was emitted as a stub" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

echo "stage2_yield_return_block_call_materialization_ok status=$status"
