#!/usr/bin/env bash
# Fast no-prelude guard for self-host HIR emit.
#
# This protects the bootstrap gate from regressing into backend/runtime stubs
# while asking only for HIR text.  The compiler under test may itself be a
# produced stage binary, so it is always invoked through run_safe.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
TIMEOUT_SEC="${P2_HIR_EMIT_TIMEOUT_SEC:-30}"
MEM_MB="${P2_HIR_EMIT_MEM_MB:-1024}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_selfhost_hir_emit_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/local_read.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/run_safe.log"

cat >"$SRC" <<'CR'
x = 1
y = x
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
  "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

if ! grep -q '\[EXIT: 0\]' "$LOG"; then
  echo "p2 selfhost HIR emit regression: compiler did not exit cleanly" >&2
  cat "$LOG" >&2
  exit 1
fi

if [[ ! -s "$OUT.hir" ]]; then
  echo "p2 selfhost HIR emit regression: missing HIR artifact" >&2
  cat "$LOG" >&2
  exit 1
fi

if ! grep -q 'func @__crystal_main' "$OUT.hir"; then
  echo "p2 selfhost HIR emit regression: HIR artifact missing __crystal_main" >&2
  cat "$OUT.hir" >&2
  exit 1
fi

if grep -q 'STUB CALLED:' "$LOG"; then
  echo "p2 selfhost HIR emit regression: runtime stub fired during HIR-only emit" >&2
  cat "$LOG" >&2
  exit 1
fi

echo "p2_selfhost_hir_emit_no_prelude_ok"
