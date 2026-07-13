#!/usr/bin/env bash
set -euo pipefail

COMPILER="${1:-bin/adamas}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/adamas_early_rebind.XXXXXX)"
SRC="$ROOT/regression_tests/complex/early_return_local_rebind_type_repro.cr"
OUT="$TMP_DIR/early_rebind"
HIR="$OUT.hir"
FUNC_HIR="$TMP_DIR/early_rebind_func.hir"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  if [[ "${KEEP_TMP:-0}" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "[p2_early_return_local_rebind_contract] kept tmp: $TMP_DIR" >&2
  fi
}
trap cleanup EXIT

"$ROOT/scripts/run_safe.sh" "$COMPILER" 180 4096 \
  "$SRC" --emit hir --no-link -o "$OUT" >"$COMPILE_LOG" 2>&1

awk '
  /^func @early_return_local_rebind\$Bool/ { in_func = 1 }
  in_func { print }
  in_func && /^}$/ { exit }
' "$HIR" >"$FUNC_HIR"

if ! grep -qF 'Array(UInt32)#<<$UInt32' "$FUNC_HIR"; then
  echo "p2_early_return_local_rebind_contract_failed: missing UInt32 array shovel" >&2
  cat "$FUNC_HIR" >&2
  exit 1
fi

if grep -qF 'Array(String)#<<$String' "$FUNC_HIR"; then
  echo "p2_early_return_local_rebind_contract_failed: stale boxed-local String fallback" >&2
  cat "$FUNC_HIR" >&2
  exit 1
fi

"$ROOT/scripts/run_safe.sh" "$COMPILER" 180 4096 \
  "$SRC" -o "$OUT" >"$COMPILE_LOG" 2>&1
"$ROOT/scripts/run_safe.sh" "$OUT" 10 512 >"$RUN_LOG" 2>&1

if ! grep -qF "early-return-local-rebind-ok" "$RUN_LOG"; then
  echo "p2_early_return_local_rebind_contract_failed: runtime mismatch" >&2
  tail -80 "$COMPILE_LOG" >&2 || true
  tail -80 "$RUN_LOG" >&2 || true
  exit 1
fi

echo "p2_early_return_local_rebind_contract_passed"
