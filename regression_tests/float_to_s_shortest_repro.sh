#!/usr/bin/env bash
# Regression: with the prelude, Float#to_s and float interpolation used the
# printf-%g intrinsic (`1.17549e-38`, `-0`). S2 emitted those strings as LLVM
# float constants and llc rejected them. They must use stdlib Float::Printer.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/float_to_s_shortest_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

status=0
check() {
  local case_name="$1" expected="$2"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
      "$WORK_DIR/$case_name.cr" -o "$WORK_DIR/$case_name" >"$WORK_DIR/$case_name.build.log" 2>&1; then
    echo "FAIL[$case_name]: compile failed" >&2
    tail -20 "$WORK_DIR/$case_name.build.log" >&2
    status=1
    return
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$case_name" 5 512 >"$WORK_DIR/$case_name.run.log" 2>&1 || true
  printf '%s\n' "$expected" >"$WORK_DIR/$case_name.expected"
  sed -n '/^=== STDERR ===$/,/^===/p' "$WORK_DIR/$case_name.run.log" | grep -v '^===' | grep -v '^\[' >"$WORK_DIR/$case_name.actual" || true
  if ! diff -u "$WORK_DIR/$case_name.expected" "$WORK_DIR/$case_name.actual" >&2; then
    echo "FAIL[$case_name]" >&2
    status=1
  fi
}

cat >"$WORK_DIR/c1.cr" <<'CR'
x = 1.1754943508222875e-38
y = 0.1
STDERR.puts x.to_s
STDERR.puts "i=#{x} #{y}"
STDERR.puts((1.0/0.0).to_s)
z = -0.0
STDERR.puts z.to_s
v = x.as(Float64 | Int32)
STDERR.puts v.to_s
STDERR.puts Float64::INFINITY == 0.0
STDERR.flush
CR
check c1 '1.1754943508222875e-38
i=1.1754943508222875e-38 0.1
Infinity
-0.0
1.1754943508222875e-38
false'

if [ "$status" -ne 0 ]; then
  echo "FAIL: Float#to_s not shortest round-trip" >&2
  exit 1
fi
echo "PASS: Float#to_s shortest OK"
