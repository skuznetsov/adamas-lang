#!/usr/bin/env bash
# Regression: Array(Int32)#index { |element| predicate } must stay on the
# inline Int32 loop path instead of expanding Indexable#index into a stdlib
# callback whose element/index types degrade during bootstrap.  This reducer
# is intentionally a no-prelude HIR probe: runtime output would not distinguish
# an ordinary fallback from the requested structural lowering.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d /tmp/adamas_index_block_int32.XXXXXX)"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_OUT="$TMP_DIR/compile.out"
COMPILE_ERR="$TMP_DIR/compile.err"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
values = [10, 20, 30]
hit = values.index { |element| element == 20 }
miss = values.index { |element| element == 99 }
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
  "$SRC" --no-prelude --emit hir --no-link -o "$BIN" >"$COMPILE_OUT" 2>"$COMPILE_ERR"
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "FAIL: index block form did not compile (status $compile_status)" >&2
  tail -100 "$COMPILE_ERR" >&2 || true
  exit 1
fi

HIR="$BIN.hir"
if [[ ! -s "$HIR" ]]; then
  echo "FAIL: no-prelude HIR artifact was not produced" >&2
  cat "$COMPILE_OUT" "$COMPILE_ERR" >&2 || true
  exit 1
fi

array_size_count="$(grep -c 'array_size' "$HIR" || true)"
index_get_count="$(grep -c 'index_get' "$HIR" || true)"
phi_count="$(grep -c ' = phi ' "$HIR" || true)"

if ! grep -Eq '^func @__adamas_main' "$HIR"; then
  echo "FAIL: HIR main function missing" >&2
  sed -n '1,120p' "$HIR" >&2
  exit 1
fi
if grep -Eq 'call .*#index' "$HIR"; then
  echo "FAIL: HIR retained an ordinary #index call" >&2
  grep -n '#index' "$HIR" >&2 || true
  exit 1
fi
if [[ "$array_size_count" -lt 2 || "$index_get_count" -lt 2 || "$phi_count" -lt 2 ]]; then
  echo "FAIL: HIR lacks the two inline search loops (array_size=$array_size_count index_get=$index_get_count phi=$phi_count)" >&2
  grep -nE 'func @__adamas_main|array_size|index_get| = phi ' "$HIR" >&2 || true
  exit 1
fi

echo "index_block_form_int32_hir_ok"
echo "array_size=$array_size_count index_get=$index_get_count phi=$phi_count"
