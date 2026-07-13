#!/usr/bin/env bash
set -euo pipefail

COMPILER="${1:-bin/adamas}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/adamas_hir_registry_remove.XXXXXX)"
BIN="$TMP_DIR/hir_registry_remove"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
  if [[ "${KEEP_TMP:-0}" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "[p2_hir_function_registry_remove_contract] kept tmp: $TMP_DIR" >&2
  fi
}
trap cleanup EXIT

"$ROOT/scripts/run_safe.sh" "$COMPILER" 360 8192 \
  "$ROOT/regression_tests/complex/hir_function_registry_lookup_probe.cr" \
  -o "$BIN" >"$COMPILE_LOG" 2>&1

"$ROOT/scripts/run_safe.sh" "$BIN" 20 2048 >"$RUN_LOG" 2>&1

if ! grep -qF "hir-function-registry-ok" "$RUN_LOG"; then
  echo "p2_hir_function_registry_remove_contract_failed" >&2
  tail -80 "$COMPILE_LOG" >&2 || true
  tail -80 "$RUN_LOG" >&2 || true
  exit 1
fi

echo "p2_hir_function_registry_remove_contract_passed"
