#!/usr/bin/env bash
# Stack-promotion soundness (2026-06-12): receiver-call trust must track
# methods returning an alias of self.
#
# The struct constructor stack-promotion (19a82ca6, extended 72c09d87)
# always trusted receiver calls on the promoted struct. A method that
# returns `self` (`def me; self; end`) hands the callee's pointer back to
# the caller; if the caller then returns it, the promoted alloca's frame
# pointer escapes `leak` -> dangling stack pointer read in main (latent
# corruption; the trivial runtime probe happens to read back intact, so
# this oracle checks the IR instead).
#
# Expected post-fix: `leak` must NOT stack-promote the constructor whose
# self-returning alias escapes via return -> the heap allocator call
# (P$Dnew) stays. A safe control (`stay`, alias consumed locally) must
# still stack-promote.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stack-self-return-alias.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "usage: $0 <adamas-compiler>" >&2
  echo "missing executable compiler: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"
LEAK_IR="$TMP_DIR/leak.ll"
STAY_IR="$TMP_DIR/stay.ll"

cat >"$SRC" <<'CR'
struct P
  def initialize(@x : Int64)
  end

  def me : P
    self
  end

  def sum : Int64
    @x
  end
end

def leak : P
  p = P.new(5_i64)
  p.me
end

def stay : Int64
  p = P.new(6_i64)
  q = p.me
  q.sum
end

a = leak
b = stay
v = a.sum + b
CR

"$COMPILER" "$SRC" --no-prelude --emit llvm-ir --no-link -o "$OUT" >"$LOG" 2>&1 || {
  echo "compile failed" >&2
  cat "$LOG" >&2
  exit 2
}

if [[ ! -s "$OUT.ll" ]]; then
  echo "missing LLVM IR: $OUT.ll" >&2
  cat "$LOG" >&2
  exit 2
fi

awk '/^define ptr @leak/{inside=1} inside{print} inside && /^}/{exit}' "$OUT.ll" >"$LEAK_IR"
awk '/^define i64 @stay/{inside=1} inside{print} inside && /^}/{exit}' "$OUT.ll" >"$STAY_IR"

if ! grep -Eq 'call ptr @P\$Dnew' "$LEAK_IR"; then
  echo "open bug reproduced: self-returning alias escapes leak() but the constructor was stack-promoted (dangling frame pointer)" >&2
  cat "$LEAK_IR" >&2
  exit 1
fi

if ! grep -Eq 'alloca %P' "$STAY_IR" || grep -Eq 'call ptr @P\$Dnew' "$STAY_IR"; then
  echo "regression: locally-consumed self-return alias must still stack-promote" >&2
  cat "$STAY_IR" >&2
  exit 1
fi

echo "fixed: self-return alias escape keeps heap allocator; local alias still stack-promotes"
