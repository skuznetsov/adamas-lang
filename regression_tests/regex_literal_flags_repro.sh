#!/usr/bin/env bash
# Regression: regex literal flags (`/re/i`, `%r(re)m`) were glued onto the
# pattern text ("re/i") and options were always 0, so S2's numeric-suffix
# regexes (`/_?(i64|...)\z/i`) never matched. Flags must become PCRE2 options.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/regex_literal_flags_repro.XXXXXX")"
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
STDERR.puts(("ABC" =~ /abc/i) ? "y" : "n")
STDERR.puts(("ABC" =~ /abc/) ? "y" : "n")
STDERR.puts "10_i64".sub(/_?(i8|i16|i32|i64|u8|f64)\z/i, "")
STDERR.puts "7_U8".sub(/_?(u8)\z/i, "")
STDERR.puts(("a\nb" =~ /a.b/m) ? "y" : "n")
STDERR.puts(("a\nb" =~ /a.b/) ? "y" : "n")
STDERR.puts(("x/y" =~ %r(x/y)) ? "y" : "n")
STDERR.puts(("X/Y" =~ %r(x/y)i) ? "y" : "n")
STDERR.puts(("ab" =~ /a b/x) ? "y" : "n")
STDERR.flush
CR
check c1 'y
n
10
7
y
n
y
y
y'

if [ "$status" -ne 0 ]; then
  echo "FAIL: regex literal flags ignored" >&2
  exit 1
fi
echo "PASS: regex literal flags OK"
