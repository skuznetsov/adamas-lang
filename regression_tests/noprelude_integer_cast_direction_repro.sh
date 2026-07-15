#!/usr/bin/env bash
# Regression: integer call-argument coercion must choose extension direction
# from the source integer signedness. Narrowing is always a bit truncation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d /tmp/adamas_integer_cast_direction.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro"
BUILD_LOG="$TMP_DIR/build.log"
IR_LOG="$TMP_DIR/repro.ll"
RUN_LOG="$TMP_DIR/run.log"

cat >"$SRC" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
  fun abort : NoReturn
end

def signed_to_int(value : Int) : Int
  value
end

def unsigned_to_int(value : Int) : Int
  value
end

signed_wide = signed_to_int(-1_i8)
unsigned_wide = unsigned_to_int(255_u8)
signed_small = (-0x1234_i64).to_i8
unsigned_small = 0x1234_u64.to_u8

if signed_wide == -1 && unsigned_wide == 255 && signed_small == -52 && unsigned_small == 52
  LibC.printf("integer_cast_direction_ok\n")
else
  LibC.abort
end
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
  "$SRC" --no-prelude --emit llvm-ir --no-link -o "$TMP_DIR/repro" >"$IR_LOG" 2>&1
ir_status=$?
set -e
if [[ $ir_status -ne 0 ]] || ! grep -q 'sext i8 .* to i32' "$IR_LOG" || \
   ! grep -q 'zext i8 .* to i32' "$IR_LOG" || \
   ! grep -q 'trunc i64 .* to i8' "$IR_LOG"; then
  echo "noprelude_integer_cast_direction_failed: LLVM cast oracle status=$ir_status" >&2
  tail -120 "$IR_LOG" >&2 || true
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
  "$SRC" --no-prelude -o "$BIN" >"$BUILD_LOG" 2>&1
compile_status=$?
set -e
if [[ $compile_status -ne 0 || ! -x "$BIN" ]]; then
  echo "noprelude_integer_cast_direction_failed: compile status=$compile_status" >&2
  tail -100 "$BUILD_LOG" >&2 || true
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e
if [[ $run_status -ne 0 ]] || ! grep -q '^integer_cast_direction_ok$' "$RUN_LOG"; then
  echo "noprelude_integer_cast_direction_failed: run status=$run_status" >&2
  cat "$RUN_LOG" >&2 || true
  exit 1
fi

echo "noprelude_integer_cast_direction_ok"
