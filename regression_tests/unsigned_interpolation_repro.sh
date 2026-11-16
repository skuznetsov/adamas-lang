#!/usr/bin/env bash
# Regression: interpolating a UInt32 or UInt64 prints it unsigned.
#
# The string_interpolation fast path in the LLVM backend converted UInt32
# through the signed i32 helper and UInt64 (also as a tagged-union arm)
# through the signed i64 helper, so "#{3278719917_u32}" printed -1016247379
# and "#{UInt64::MAX}" printed -1. UInt32 now widens with zext to the i64
# helper and UInt64 uses an unsigned i64 helper. Signed and narrow unsigned
# parts are the controls. Interpolation needs the prelude, so this checks the
# full prelude program against fixed expected output.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/unsigned-interpolation.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/u.cr" <<'CR'
def pick(flag : Bool) : UInt64 | String
  flag ? 18446744073709551615_u64 : "s"
end

def pick32(flag : Bool) : UInt32 | String
  flag ? 4294967295_u32 : "s"
end

a = 3278719917_u32
b = 18446744073709551615_u64
STDERR.puts "u32=#{a}"
STDERR.puts "u64=#{b}"
STDERR.puts "u64arm=#{pick(true)}"
STDERR.puts "u32arm=#{pick32(true)}"
STDERR.puts "i32=#{-5}"
STDERR.puts "i64=#{-9000000000_i64}"
STDERR.puts "u8=#{200_u8}"
STDERR.puts "u16=#{65535_u16}"
CR

expected='u32=3278719917
u64=18446744073709551615
u64arm=18446744073709551615
u32arm=4294967295
i32=-5
i64=-9000000000
u8=200
u16=65535'

strip() { grep -v '^\[RUN_SAFE\|^\[EXIT\|^===' || true; }

if [[ -n "$CRYSTAL_BIN" ]]; then
  "$CRYSTAL_BIN" build "$WORK_DIR/u.cr" -o "$WORK_DIR/u_oracle" > "$WORK_DIR/oracle.log" 2>&1
  oracle_out="$("$SAFE_RUNNER" "$WORK_DIR/u_oracle" 5 256 2>&1 | strip)"
  if [[ "$oracle_out" != "$expected" ]]; then
    echo "ORACLE_MISMATCH: $oracle_out" >&2
    exit 1
  fi
fi

if ! "$SAFE_RUNNER" "$ADAMAS_BIN" 300 6144 "$WORK_DIR/u.cr" -o "$WORK_DIR/u" > "$WORK_DIR/build.log" 2>&1 || [[ ! -x "$WORK_DIR/u" ]]; then
  echo "FAIL: unsigned interpolation program did not compile" >&2
  strip < "$WORK_DIR/build.log" | tail -5 >&2
  exit 1
fi

set +e
out="$("$SAFE_RUNNER" "$WORK_DIR/u" 5 256 2>&1)"
status=$?
set -e
printed="$(printf '%s\n' "$out" | strip)"
if [[ $status -ne 0 || "$printed" != "$expected" ]]; then
  echo "FAIL: exit=$status" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$printed") >&2 || true
  exit 1
fi
echo "PASS unsigned_interpolation"
