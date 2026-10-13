#!/usr/bin/env bash
# Calling a method on an all-reference nilable union (String | Nil) goes through
# class vdispatch with a null guard. The null branch returned a placeholder
# (null/first arg) instead of running Nil's own implementation, so
# `(nil.as(String?)).inspect` produced a null String and crashed.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nilable_reference_vdispatch_nil_branch_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
def g(b : Bool) : String?
  b ? "s" : nil
end

def h(b : Bool) : String?
  b ? "t#{1}" : nil
end

v = g(false)
STDERR.puts "a=#{v.inspect.size} #{v.inspect}"
w = g(true)
STDERR.puts "b=#{w.inspect}"
x = h(false)
STDERR.puts "c=#{x.to_s.size} [#{x.to_s}]"
STDERR.puts "d=#{x == nil} #{h(true) == "t1"}"
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
a=3 nil
b="s"
c=0 []
d=true true
OUT
grep -E '^[a-d]=' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: nilable reference vdispatch runs Nil's implementation on null" >&2
  exit 1
fi
echo "PASS: nilable reference vdispatch runs Nil's implementation on null"
