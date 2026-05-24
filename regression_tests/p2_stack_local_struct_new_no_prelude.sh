#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cv2-stack-struct-new.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "usage: $0 <crystal-v2-compiler>" >&2
  echo "missing executable compiler: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"
MAIN_IR="$TMP_DIR/main.ll"
MAKE_IR="$TMP_DIR/make_pair.ll"
ARG_SRC="$TMP_DIR/arg_escape_guard.cr"
ARG_OUT="$TMP_DIR/arg_escape_guard"
ARG_MAIN_IR="$TMP_DIR/arg_escape_guard_main.ll"

cat >"$SRC" <<'CR'
struct Pair
  def initialize(@x : Int64, @y : Int64)
  end

  def sum : Int64
    @x + @y
  end
end

struct Quad
  def initialize(@a : Pair, @b : Pair)
  end

  def sum : Int64
    @a.sum + @b.sum
  end
end

def make_pair : Pair
  Pair.new(9_i64, 10_i64)
end

q = Quad.new(Pair.new(1_i64, 2_i64), Pair.new(3_i64, 4_i64))
v = q.sum + make_pair.sum
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 2048 \
  "$SRC" --no-prelude --emit llvm-ir --no-link -o "$OUT" >"$LOG" 2>&1

if [[ ! -s "$OUT.ll" ]]; then
  echo "missing LLVM IR: $OUT.ll" >&2
  cat "$LOG" >&2
  exit 1
fi

awk '/^define void @__crystal_main/{inside=1} inside{print} inside && /^}/{exit}' "$OUT.ll" >"$MAIN_IR"
awk '/^define ptr @make_pair/{inside=1} inside{print} inside && /^}/{exit}' "$OUT.ll" >"$MAKE_IR"

if grep -Eq 'call ptr @(Pair|Quad)\$Dnew' "$MAIN_IR"; then
  echo "expected stack-local struct constructors to be inlined in __crystal_main" >&2
  cat "$MAIN_IR" >&2
  exit 1
fi

if ! grep -Eq 'alloca %Pair' "$MAIN_IR" || ! grep -Eq 'alloca %Quad' "$MAIN_IR"; then
  echo "expected __crystal_main to allocate local Pair and Quad values on the stack" >&2
  cat "$MAIN_IR" >&2
  exit 1
fi

if ! grep -Eq 'call ptr @Pair\$Dnew' "$MAKE_IR"; then
  echo "expected escaping return constructor in make_pair to keep the heap allocator call" >&2
  cat "$MAKE_IR" >&2
  exit 1
fi

cat >"$ARG_SRC" <<'CR'
struct Pair
  def initialize(@x : Int64, @y : Int64)
  end

  def sum : Int64
    @x + @y
  end
end

def consume(pair : Pair) : Int64
  pair.sum
end

v = consume(Pair.new(1_i64, 2_i64))
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 2048 \
  "$ARG_SRC" --no-prelude --emit llvm-ir --no-link -o "$ARG_OUT" >"$LOG" 2>&1

awk '/^define void @__crystal_main/{inside=1} inside{print} inside && /^}/{exit}' "$ARG_OUT.ll" >"$ARG_MAIN_IR"
if ! grep -Eq 'call ptr @Pair\$Dnew' "$ARG_MAIN_IR"; then
  echo "expected arbitrary method argument constructor to keep the heap allocator call" >&2
  cat "$ARG_MAIN_IR" >&2
  exit 1
fi

echo "not reproduced: stack-local struct .new is inlined while escaping/unsafe-arg .new stays heap-backed"
