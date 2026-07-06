#!/usr/bin/env bash
# Repro: a call returning UInt32 must keep its unsignedness for downstream
# div/rem signedness selection.
#
# Root cause (fixed): emit_call's final value_types update mapped the EMITTED
# LLVM return string back to a TypeRef ("i32" -> INT32), erasing unsignedness.
# ~UInt32.new(0) // 10 then emitted `sdiv` (~0 = -1 signed -> quotient 0), so
# String#to_unsigned_info computed mul_overflow = 0 and every multi-digit
# to_i?/to_u*? parse bailed out after the first digit ("64".to_i? == 6).
#
# GREEN: the division of the bitnot'd UInt32 call result emits udiv, not sdiv.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/call_unsigned_div.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/compile.log"
FUNC_IR="$TMP_DIR/func.ll"

cat > "$SRC" <<'CR'
def gv : UInt32
  0_u32
end

def probe : UInt32
  n = ~gv
  n // 10
end

probe
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 \
  "$SRC" --no-prelude --emit llvm-ir --no-link -o "$OUT" >"$LOG" 2>&1

IR="$OUT.ll"
if [[ ! -s "$IR" ]]; then
  echo "call_unsigned_div_failed: missing IR" >&2
  tail -60 "$LOG" >&2 || true
  exit 1
fi

awk '
  /^define .*@probe/ { inside = 1 }
  inside { print }
  inside && /^}/ { exit }
' "$IR" > "$FUNC_IR"

if [[ ! -s "$FUNC_IR" ]]; then
  echo "call_unsigned_div_failed: probe function not found in IR" >&2
  grep -n 'define.*probe' "$IR" >&2 || true
  exit 1
fi

if grep -q 'sdiv' "$FUNC_IR"; then
  echo "call_unsigned_div_failed: UInt32 division emitted sdiv" >&2
  cat "$FUNC_IR" >&2
  exit 1
fi

if ! grep -q 'udiv' "$FUNC_IR"; then
  echo "call_unsigned_div_failed: no udiv found for UInt32 division" >&2
  cat "$FUNC_IR" >&2
  exit 1
fi

echo "call_unsigned_div_ok"
