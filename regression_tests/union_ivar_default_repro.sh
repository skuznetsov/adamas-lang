#!/usr/bin/env bash
# A union-typed ivar with a declared default (`@a : String? = "A"`) was skipped
# by the allocator's union branch, so the field stayed zero (nil) and the
# default was silently lost.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union_ivar_default.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
class Foo
  @a : String? = "A"
  @b : Int32 = 5
  @d : Int32? = 3
  @f : Bool? = true
  @g : Int32? = nil

  def run
    STDERR.puts "F a=#{@a.nil?}#{@a} b=#{@b} d=#{@d.nil?}#{@d} f=#{@f.nil?}#{@f} g=#{@g.nil?}"
  end
end

class Bar
  @s : String? = "s"

  def initialize(@x : Int32)
    @s = nil if @x > 1
  end

  def run
    STDERR.puts "B x=#{@x} s=#{@s.nil?}#{@s}"
  end
end

Foo.new.run
Bar.new(1).run
Bar.new(2).run
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
F a=falseA b=5 d=false3 f=falsetrue g=true
B x=1 s=falses
B x=2 s=true
OUT
grep -E '^[FB] ' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: union ivar declared default" >&2
  exit 1
fi
echo "PASS: union ivar declared defaults are stored by the allocator"
