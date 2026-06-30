#!/usr/bin/env bash
# Regression: self-compiling the compiler must materialize
# AstToHir#contains_yield_deep? for the non-nil ArenaLike union call shape.
# The registered method accepts ArenaLike?, and a non-nil ArenaLike union is a
# subtype of that nilable union; it must not fall through to an undefined-extern
# abort stub.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_contains_yield_deep.XXXXXX")"
OUT="$TMP_DIR/adamas_self"
LOG="$TMP_DIR/compile.log"
trap 'rm -rf "$TMP_DIR"' EXIT

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 240 8192 "$ROOT_DIR/src/adamas.cr" -o "$OUT" --emit llvm-ir --no-link >"$LOG" 2>&1
status=$?
set -e

if [[ $status -ne 0 ]]; then
  echo "FAIL: compiler self-IR build failed (status $status)" >&2
  tail -120 "$LOG" >&2
  exit 2
fi

LL="${OUT}.ll"
if [[ ! -f "$LL" ]]; then
  echo "FAIL: expected LLVM IR was not written: $LL" >&2
  tail -120 "$LOG" >&2
  exit 2
fi

if grep -Fq 'STUB CALLED: Adamas$CCHIR$CCAstToHir$Hcontains_yield_deep' "$LL"; then
  echo "FAIL: contains_yield_deep? non-nil ArenaLike call shape still lowers to an abort stub" >&2
  grep -n -F 'STUB CALLED: Adamas$CCHIR$CCAstToHir$Hcontains_yield_deep' "$LL" >&2 || true
  exit 1
fi

if ! grep -Fq 'Adamas$CCHIR$CCAstToHir$Hcontains_yield_deep' "$LL"; then
  echo "FAIL: contains_yield_deep? materialization not found in self IR" >&2
  exit 1
fi

echo "stage2_contains_yield_deep_materialization_ok"
