#!/usr/bin/env bash
# Regression: produced s2b must materialize AstToHir#lower_block_to_proc
# instead of emitting an undefined-extern abort stub for full-prelude block
# lowering.
#
# This is a focused frontier guard, not a full s2b readiness test: downstream
# HIR->MIR lowering may still fail after this materialization contract is fixed.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_lower_block_to_proc.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/puts42.cr"
OUT="$TMP_DIR/puts42"
LOG="$TMP_DIR/compile.log"

cat > "$SRC" <<'CR'
puts 42
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 "$SRC" -o "$OUT" >"$LOG" 2>&1
status=$?
set -e

if grep -Fq "error: Unreachable" "$LOG"; then
  echo "FAIL: did not reach the lower_block_to_proc materialization frontier" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

if grep -Fq "STUB CALLED: Adamas\$CCHIR\$CCAstToHir\$Hlower_block_to_proc" "$LOG"; then
  echo "FAIL: lower_block_to_proc was emitted as a stub" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

echo "stage2_lower_block_to_proc_materialization_ok status=$status"
