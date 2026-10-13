#!/usr/bin/env bash
# `String < String` / `>` / `<=` / `>=` were lowered through lower_binary's raw
# primitive table (String counted as a primitive operand for every operator), so
# they compared the two string pointers — `"b" > "a"` folded to false. Relational
# ops on String must dispatch to Comparable via String#<=>.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/string_comparable_relational_op_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
x = "b"
y = "a"
STDERR.puts "gt #{x > y} #{y > x}"
STDERR.puts "lt #{x < y} #{y < x}"
STDERR.puts "ge #{x >= y} #{x >= "b"}"
STDERR.puts "le #{x <= y} #{y <= "a"}"
STDERR.puts "eq #{x == "b"} #{x != "b"}"
STDERR.puts "max #{["b", "d", "a"].max}"
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
printf 'gt true false\nlt false true\nge true true\nle false true\neq true false\nmax d\n' >"$WORK_DIR/expected"
grep -E '^(gt|lt|ge|le|eq|max) ' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: String relational operators did not dispatch through Comparable" >&2
  exit 1
fi
echo "PASS: String relational operators dispatch through Comparable"
