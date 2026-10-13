#!/usr/bin/env bash
# A block containing `next` is not inlined into a yielding callee; the caller
# passes the block thunk as a trailing argument instead
# (inline_yield_fallback_call). A def that uses bare `yield` without a source
# `&block` slot was lowered with no block parameter, so MIR found no yield
# target and replaced every `yield` with nil: the block body never ran.
# The value cases (`twice`) also need the block param types inferred from the
# callee's yield args; otherwise the thunk returns through a POINTER slot and
# the callee sees a VOID yield result.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bare_yield_next.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_inst.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Cli
  def initialize(@a : Int32, @b : Int32)
  end

  def each_v
    yield @a
    yield @b
  end

  def twice(x : Int32)
    yield(x) + yield(x + 1)
  end

  def run : Int32
    acc = 0
    each_v do |x|
      next if x == 5
      acc += x
    end
    acc
  end

  def run_value : Int32
    twice(4) do |x|
      next 100 if x == 4
      x
    end
  end
end
c = Cli.new(7, 5)
LibC.exit(1) unless c.run == 7
LibC.exit(2) unless c.run_value == 105
LibC.exit(0)
CR
cat >"$WORK_DIR/np_cls.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Util
  def self.each_v
    yield 7
    yield 5
  end

  def self.twice(x : Int32)
    yield(x) + yield(x + 1)
  end
end
acc = 0
Util.each_v do |x|
  next if x == 5
  acc += x
end
LibC.exit(1) unless acc == 7
v = Util.twice(4) do |x|
  next 100 if x == 4
  x
end
LibC.exit(v == 105 ? 0 : 2)
CR
cat >"$WORK_DIR/np_mod.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Util
  def self.each_v
    yield 7
    yield 5
  end

  def self.twice(x : Int32)
    yield(x) + yield(x + 1)
  end
end
acc = 0
Util.each_v do |x|
  next if x == 5
  acc += x
end
LibC.exit(1) unless acc == 7
v = Util.twice(4) do |x|
  next 100 if x == 4
  x
end
LibC.exit(v == 105 ? 0 : 2)
CR
cat >"$WORK_DIR/np_top.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def each_v
  yield 7
  yield 5
end
def run : Int32
  acc = 0
  each_v do |x|
    next if x == 5
    acc += x
  end
  acc
end
LibC.exit(run == 7 ? 0 : 1)
CR
cat >"$WORK_DIR/pl_inst.cr" <<'CR'
class Cli
  def initialize(@items : Array(String))
  end

  def each_item
    @items.each { |s| yield s }
  end

  def joined : String
    out = [] of String
    each_item do |s|
      next if s.empty?
      out << s
    end
    out.join(",")
  end
end
r = Cli.new(["a", "", "b"]).joined
STDERR.puts r
exit 1 unless r == "a,b"
exit 0
CR
for name in np_inst np_cls np_mod np_top pl_inst; do
  flags=()
  [[ "$name" == np_* ]] && flags=(--no-prelude)
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
      "$WORK_DIR/$name.cr" ${flags[@]+"${flags[@]}"} -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1; then
    echo "case $name failed:" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo bare_yield_next_block_fallback_repro_ok
