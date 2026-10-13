#!/usr/bin/env bash
# Regression: `Foo.new(x) { ... }` reaching a yielding `initialize(a, &)`.
# The synthesized allocator overload `Foo.new$..._block` added its forwarded
# block param without the block flag, so callers coerced the block argument
# to a heap Proc box (make_proc) unless the formal happened to be named
# `block`. The initializer then yielded through the raw fn-pointer ABI into
# that box: SIGBUS (exit 138). Original-stdlib `Process#initialize(args, *,
# env, ..., &)` hits this shape.
# Cases: anonymous `&` with a void block, a named-arg + protected overload
# with two block params, a bare-yield initializer (implicit block), and a
# non-void block whose value the initializer uses, plus the two heap-Proc
# carriers (`block.call`, captured `&@ivar`). Each prints EXIT 8.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/new_block_yield_init.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/anon.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Foo
  getter v : Int32
  def initialize(a : Int32, &)
    @v = a + 5
    yield a
  end
end
f = Foo.new(3) { |e| LibC.exit(99) if e > 1000 }
LibC.exit(f.v)
CR

cat >"$WORK_DIR/named_protected.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Foo
  getter v : Int32
  def self.make(x : Int32) : Foo
    new(x, k: 5) do |e, c|
      LibC.exit(100 + e + c) if e > 1000
    end
  end
  def initialize(@v : Int32)
  end
  protected def initialize(a : Int32, *, k : Int32 = 1, &)
    @v = a + k
    yield a, k
  end
end
LibC.exit(Foo.make(3).v)
CR

cat >"$WORK_DIR/bare_yield.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Foo
  getter v : Int32
  def initialize(a : Int32)
    @v = a + 5
    yield a
  end
end
f = Foo.new(3) { |e| LibC.exit(99) if e > 1000 }
LibC.exit(f.v)
CR

cat >"$WORK_DIR/value_block.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Foo
  getter v : Int32
  def initialize(a : Int32, & : Int32 -> Int32)
    @v = yield a
  end
end
f = Foo.new(3) { |e| e + 5 }
LibC.exit(f.v)
CR

# Heap-Proc carriers must keep working: a `block.call` initializer and a
# captured `&@ivar` initializer take a materialized Proc, not a raw callback.
cat >"$WORK_DIR/heap_call.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Foo
  getter v : Int32
  def initialize(a : Int32, &block : Int32 -> Int32)
    @v = block.call(a)
  end
end
f = Foo.new(3) { |e| e + 5 }
LibC.exit(f.v)
CR

cat >"$WORK_DIR/captured_ivar.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Foo
  def initialize(@a : Int32, &@func : Int32 -> Int32)
  end
  def run : Int32
    @func.call(@a)
  end
end
f = Foo.new(3) { |e| e + 5 }
LibC.exit(f.run)
CR

for name in anon named_protected bare_yield value_block heap_call captured_ivar; do
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    echo "case $name: compile failed" >&2
    tail -20 "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 8\]' "$WORK_DIR/$name.run.log"; then
    echo "case $name failed (want EXIT 8):" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo new_block_yield_initialize_repro_ok
