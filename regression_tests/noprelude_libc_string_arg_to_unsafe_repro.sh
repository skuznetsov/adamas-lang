#!/bin/bash
# Regression: a String literal/var passed to an extern-C (lib) function in
# --no-prelude mode must be coerced to its +12 char-data pointer (to_unsafe),
# NOT passed as the raw Crystal String object whose header byte (type_id=0x10)
# the C function would read as the whole string.
#
# Root cause (fixed 2026-05-30): HIR try_implicit_to_unsafe gated the String
# auto-coercion on a registered String#to_unsafe method, which is absent in
# --no-prelude. Fix routes String args through the always-emitted runtime
# helper __adamas_string_to_unsafe (GEP i8 +12). Covers fixed AND varargs args.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/noprelude_libc_str_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- Case 1: format string (fixed param) + integer arithmetic varargs ---
SRC1="$TMP_DIR/printf_arith.cr"
BIN1="$TMP_DIR/printf_arith"
cat >"$SRC1" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
end
a = 10
b = 3
LibC.printf("%d %d %d %d %d\n", a + b, a - b, a * b, a / b, a % b)
CR

"$COMPILER" "$SRC1" --no-prelude -o "$BIN1" >"$TMP_DIR/c1.log" 2>&1
OUT1="$("$BIN1" 2>/dev/null || true)"
if [[ "$OUT1" != "13 7 30 3 1" ]]; then
  echo "FAIL case1: expected '13 7 30 3 1', got '$OUT1'" >&2
  exit 1
fi

# --- Case 2: String passed in a variadic %s position ---
SRC2="$TMP_DIR/printf_s.cr"
BIN2="$TMP_DIR/printf_s"
cat >"$SRC2" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
end
name = "world"
LibC.printf("hi %s end\n", name)
CR

"$COMPILER" "$SRC2" --no-prelude -o "$BIN2" >"$TMP_DIR/c2.log" 2>&1
OUT2="$("$BIN2" 2>/dev/null || true)"
if [[ "$OUT2" != "hi world end" ]]; then
  echo "FAIL case2 (varargs %s): expected 'hi world end', got '$OUT2'" >&2
  exit 1
fi

# --- Case 3: explicit String#to_unsafe in --no-prelude (was an abort stub) ---
SRC3="$TMP_DIR/printf_tounsafe.cr"
BIN3="$TMP_DIR/printf_tounsafe"
cat >"$SRC3" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
end
LibC.printf("hello\n".to_unsafe)
CR

"$COMPILER" "$SRC3" --no-prelude -o "$BIN3" >"$TMP_DIR/c3.log" 2>&1
OUT3="$("$BIN3" 2>/dev/null || true)"
if [[ "$OUT3" != "hello" ]]; then
  echo "FAIL case3 (explicit .to_unsafe): expected 'hello', got '$OUT3'" >&2
  exit 1
fi

# explicit to_unsafe body must be GEP+12, not an abort stub
"$COMPILER" "$SRC3" --no-prelude --emit llvm-ir -o "$TMP_DIR/ir3" >/dev/null 2>&1
if grep -A3 'define ptr @String\$Hto_unsafe' "$TMP_DIR/ir3.ll" | grep -q 'abort'; then
  echo "FAIL: String#to_unsafe still emits an abort stub in --no-prelude" >&2
  exit 1
fi

# --- IR check: format arg goes through the to_unsafe helper, not raw @.str ---
"$COMPILER" "$SRC1" --no-prelude --emit llvm-ir -o "$TMP_DIR/ir_out" >/dev/null 2>&1
IR="$TMP_DIR/ir_out.ll"
if ! grep -Eq 'call ptr @__adamas_string_to_unsafe\(ptr @\.str' "$IR"; then
  echo "FAIL: expected __adamas_string_to_unsafe coercion of the format literal" >&2
  exit 1
fi

echo "PASS: noprelude_libc_string_arg_to_unsafe (fixed + varargs + IR)"
