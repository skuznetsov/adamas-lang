#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  echo "requires: compiler built with -Ddebug_hooks" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/lower-call-arena-ledger.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$SRC" <<'CR'
def identity(x)
  x
end

identity(1)
CR

set +e
ADAMAS_LOWER_CALL_ARENA_LEDGER=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 4096 \
  "$SRC" --no-prelude -o "$OUT" >"$LOG" 2>&1
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "FAIL: compiler exited with rc=$rc" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if ! grep -q '^\[LC_ARENA\]' "$LOG"; then
  echo "FAIL: no [LC_ARENA] rows emitted" >&2
  echo "hint: build the compiler with -Ddebug_hooks" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if ! grep -q 'kind=expr' "$LOG"; then
  echo "FAIL: no lower-call expr rows emitted" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if ! grep -q 'kind=phase' "$LOG"; then
  echo "FAIL: no lower-call phase rows emitted" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if ! grep -q 'ref_origin=' "$LOG"; then
  echo "FAIL: no AstNodeRef origin emitted" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

if ! grep -q 'ref_span=' "$LOG"; then
  echo "FAIL: no AstNodeRef span emitted" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

echo "PASS lower_call_arena_ledger"
