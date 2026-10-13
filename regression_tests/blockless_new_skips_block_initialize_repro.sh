#!/usr/bin/env bash
# Regression: blockless `Foo.new` ran a block-requiring initialize.
# The base allocator `Foo.new` took its parameters from the FIRST initialize
# seen in the class body. When that initialize captured a block
# (`&@func : Foo -> Int32`, or used `yield`), a later zero-arg initialize was
# ignored, so `Foo.new` passed a null block and skipped the blockless body.
# Block calls already have their own `Foo.new$..._block` overload, so a
# block-requiring initialize is only a provisional base: a later blockless
# initialize with no required params replaces it.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/blockless_new_skips_block_initialize_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/bn.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

class Foo
  @func : Foo -> Int32
  @kind : Int32

  def initialize(@name : Int32? = nil, &@func : Foo -> Int32)
    @kind = 1
  end

  def initialize
    @func = ->(t : Foo) { 0 }
    @kind = 2
  end

  def kind
    @kind
  end

  def run
    @func.call(self)
  end
end

class Bar
  @kind : Int32

  def initialize(x : Int32 = 3)
    @kind = yield x
  end

  def initialize
    @kind = 9
  end

  def kind
    @kind
  end
end

code = 0
g = Foo.new { |x| 40 }
f = Foo.new
code |= 1 unless f.kind == 2
code |= 2 unless g.kind == 1 && g.run == 40
code |= 4 unless f.run == 0
code |= 8 unless Bar.new.kind == 9
code |= 16 unless Bar.new { |x| x + 1 }.kind == 4
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/bn.cr" --no-prelude -o "$WORK_DIR/bn" >"$WORK_DIR/bn.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/bn.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/bn" 5 512 >"$WORK_DIR/bn.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/bn.run.log"; then
  echo "FAIL: blockless Foo.new did not use the blockless initialize" >&2
  cat "$WORK_DIR/bn.run.log" >&2
  exit 1
fi
echo "PASS: blockless Foo.new uses the blockless initialize"
