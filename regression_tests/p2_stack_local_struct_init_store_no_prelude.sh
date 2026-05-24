#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cv2-stack-struct-init-store.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "usage: $0 <crystal-v2-compiler>" >&2
  echo "missing executable compiler: $COMPILER" >&2
  exit 2
fi

TRIVIAL_SRC="$TMP_DIR/trivial.cr"
TRIVIAL_OUT="$TMP_DIR/trivial"
CUSTOM_SRC="$TMP_DIR/custom.cr"
CUSTOM_OUT="$TMP_DIR/custom"
PADDED_SRC="$TMP_DIR/padded.cr"
PADDED_OUT="$TMP_DIR/padded"
LOG="$TMP_DIR/compile.log"
MAIN_IR="$TMP_DIR/main.ll"
CUSTOM_MAIN_IR="$TMP_DIR/custom_main.ll"
PADDED_MAIN_IR="$TMP_DIR/padded_main.ll"

cat >"$TRIVIAL_SRC" <<'CR'
struct Pair
  def initialize(@x : Int64, @y : Int64)
  end

  def sum : Int64
    @x + @y
  end
end

pair = Pair.new(1_i64, 2_i64)
z = pair.sum
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 2048 \
  "$TRIVIAL_SRC" --no-prelude --emit llvm-ir --no-link -o "$TRIVIAL_OUT" >"$LOG" 2>&1

awk '/^define void @__crystal_main/{inside=1} inside{print} inside && /^}/{exit}' "$TRIVIAL_OUT.ll" >"$MAIN_IR"

if grep -Eq 'call .*@Pair\$Hinitialize' "$MAIN_IR"; then
  echo "expected trivial stack-local Pair.new to inline initializer field stores" >&2
  cat "$MAIN_IR" >&2
  exit 1
fi

if grep -Eq 'llvm\.memset' "$MAIN_IR"; then
  echo "expected fully-initialized trivial Pair.new to skip zero-fill" >&2
  cat "$MAIN_IR" >&2
  exit 1
fi

if ! grep -Eq 'store i64 1, ptr' "$MAIN_IR" || ! grep -Eq 'store i64 2, ptr' "$MAIN_IR"; then
  echo "expected direct field stores for trivial Pair.new" >&2
  cat "$MAIN_IR" >&2
  exit 1
fi

cat >"$CUSTOM_SRC" <<'CR'
struct Pair
  def initialize(@x : Int64, @y : Int64)
    @x = @x + 1_i64
  end
end

pair = Pair.new(1_i64, 2_i64)
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 2048 \
  "$CUSTOM_SRC" --no-prelude --emit llvm-ir --no-link -o "$CUSTOM_OUT" >"$LOG" 2>&1

awk '/^define void @__crystal_main/{inside=1} inside{print} inside && /^}/{exit}' "$CUSTOM_OUT.ll" >"$CUSTOM_MAIN_IR"

if ! grep -Eq 'call .*@Pair\$Hinitialize' "$CUSTOM_MAIN_IR"; then
  echo "expected non-trivial initialize body to stay as a real initializer call" >&2
  cat "$CUSTOM_MAIN_IR" >&2
  exit 1
fi

if ! grep -Eq 'llvm\.memset' "$CUSTOM_MAIN_IR"; then
  echo "expected non-trivial initialize fallback to preserve zero-fill" >&2
  cat "$CUSTOM_MAIN_IR" >&2
  exit 1
fi

cat >"$PADDED_SRC" <<'CR'
struct Padded
  def initialize(@tag : UInt8, @value : Int32)
  end
end

padded = Padded.new(1_u8, 42_i32)
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 2048 \
  "$PADDED_SRC" --no-prelude --emit llvm-ir --no-link -o "$PADDED_OUT" >"$LOG" 2>&1

awk '/^define void @__crystal_main/{inside=1} inside{print} inside && /^}/{exit}' "$PADDED_OUT.ll" >"$PADDED_MAIN_IR"

if grep -Eq 'call .*@Padded\$Hinitialize' "$PADDED_MAIN_IR"; then
  echo "expected padded trivial initializer to inline direct field stores" >&2
  cat "$PADDED_MAIN_IR" >&2
  exit 1
fi

if ! grep -Eq 'llvm\.memset' "$PADDED_MAIN_IR"; then
  echo "expected padded trivial initializer to keep zero-fill for padding bytes" >&2
  cat "$PADDED_MAIN_IR" >&2
  exit 1
fi

echo "p2_stack_local_struct_init_store_no_prelude_ok"
