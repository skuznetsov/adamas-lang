#!/usr/bin/env bash
# A block shorthand whose call takes a block must keep parsing the member
# chain after that block: `&.map { |v| v }.add(1)`. Commit 8586cd9a dropped
# the loop that did this, so inside call parentheses the trailing `.add(1)`
# was left behind and the parser stopped with "unexpected RParen" (the stage-1
# compiler rejected `x.try(&.map { |v| v }.join(","))` in its own sources).
# The Amp and AmpDot branches of parse_block_shorthand now share one
# chain-and-block helper. Each case exits 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/block-shorthand-chain.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end

  @[Primitive(:binary)]
  def *(other : Int32) : Int32
  end
end

class Box
  def initialize(@v : Int32)
  end

  def map(& : Int32 -> Int32) : Box
    Box.new(yield @v)
  end

  def add(o : Int32) : Int32
    @v + o
  end
end

def with_box(& : Box -> Int32) : Int32
  yield Box.new(1)
end

def try_it(b : Box, & : Box -> Int32) : Int32
  yield b
end
CR

# name|expression yielding 42
CASES=(
  'only_arg|with_box(&.map { |v| v + 40 }.add(1))'
  'after_positional|try_it(Box.new(1), &.map { |v| v + 10 }.add(31))'
  'two_blocks|try_it(Box.new(2), &.map { |v| v + 1 }.map { |v| v * 2 }.add(36))'
  'do_end|try_it(Box.new(3), &.map do |v| v * 2 end.add(36))'
  'no_paren_arg|try_it(Box.new(1), &.map { |v| v }.add 41)'
  'no_parens_call|try_it Box.new(0), &.map { |v| v }.add(42)'
)

# Assign first: a multi-argument call without parentheses nested inside
# another call's parentheses is a separate parser gap.
for entry in "${CASES[@]}"; do
  name="${entry%%|*}"
  { cat "$WORK_DIR/header.cr"; printf 'r = %s\nLibC.exit(r)\n' "${entry#*|}"; } > "$WORK_DIR/$name.cr"
done

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%|*}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "42" ]]; then
      printf 'ORACLE FAIL: original %s did not exit 42\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%|*}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|unexpected\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected 42\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d block shorthand chain case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'block shorthand chain cases passed\n'
