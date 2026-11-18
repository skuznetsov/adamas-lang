#!/usr/bin/env bash
# Regression: interpolating a Symbol prints its name.
#
# A Symbol is an i32 symbol-table index. The LLVM string-interpolation
# lowering had no Symbol case: a scalar Symbol fell into the generic i32 arm
# and printed its index (`"#{:a}"` -> "0"), and a Symbol arm of a union fell
# into the pointer arm, which read the index as a String pointer (garbage or a
# hang). Both now call the backend-owned Symbol#to_s body.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/symbol-interpolation.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/m.cr" <<'CR'
s = :interp
STDERR.puts "sym=#{s}"
STDERR.puts "lit=#{:lit} q=#{:"two words"}"
v = ARGV.empty? ? :left : "right"
STDERR.puts "u=#{v}"
b = [0, :key]
STDERR.puts "b=#{b[1]}"
w = ARGV.empty? ? :only : nil
STDERR.puts "n=#{w}|"
c = [1.5, :fl, 'c']
STDERR.puts "c=#{c[1]} #{c[0]} #{c[2]}"
STDERR.puts "#{:a}#{:b}"
CR

expected='sym=interp
lit=lit q=two words
u=left
b=key
n=only|
c=fl 1.5 c
ab'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===\|^\[KILL\|^\[CRASH' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/m.cr" -o "$WORK_DIR/m_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/m_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/m.cr" -o "$WORK_DIR/m" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/m" ]]; then
  echo "FAIL: program did not compile" >&2
  strip < "$WORK_DIR/build.log" | grep -i error | head -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/m" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi

echo "PASS: Symbol interpolation prints names"
