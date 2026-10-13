#!/usr/bin/env bash
# A block containing `next` passed to a user yield method is lowered as a
# raw block thunk whose captures live in global closure cells. The cell
# stores were hoisted to the captured value's origin block (the function
# entry for params), i.e. BEFORE a recursive call made earlier in the same
# method. The recursive call overwrote the cells, so the outer block saw the
# callee's values. In stage2 this clobbered `class_name` inside
# register_concrete_class's `each_param do ... next ... end` after the
# nested-class recursion, registering methods under the wrong owner.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/closure_cell_recursion.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_rec.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Acc
  def initialize
    @sum = 0
  end
  def add(n : Int32)
    @sum = @sum * 1000 + n
  end
  def sum : Int32
    @sum
  end
end
class R
  def each_p(&)
    yield 3
  end

  def reg(acc : Acc, v : Int32, depth : Int32)
    reg(acc, v + 10, 1) if depth == 0
    each_p do |x|
      next if x == 99
      acc.add(depth * 100 + v)
    end
  end
end
acc = Acc.new
R.new.reg(acc, 1, 0)
# Inner call records 111, outer call must record 1 (not 111 again).
LibC.exit(1) unless acc.sum == 111001
LibC.exit(0)
CR
cat >"$WORK_DIR/pl_rec.cr" <<'CR'
class R
  getter seen = [] of String

  def each_p(arr : Array(Int32), &)
    yield arr[0]
  end

  def reg(name : String, depth : Int32)
    reg(name + "::A", 1) if depth == 0
    each_p([3]) do |x|
      next if x == 99
      @seen << "#{depth}:#{name}"
    end
  end
end
r = R.new
r.reg("Foo", 0)
STDERR.puts r.seen.join(",")
exit 1 unless r.seen.join(",") == "1:Foo::A,0:Foo"
exit 0
CR
for name in np_rec pl_rec; do
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
echo closure_cell_recursion_next_block_repro_ok
