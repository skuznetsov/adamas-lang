#!/usr/bin/env bash
# `x.is_a?(T) && rhs` must narrow `x : T` while lowering `rhs`.
# lower_short_circuit / lower_short_circuit_condition applied only nil
# narrowing to the RHS, so `ev.elements` on an abstract parent became an
# unknown-typed virtual call and `.size >= 2` lost its target: the `&&`
# evaluated wrongly. In stage1 this broke MacroExpander#evaluate_for_block
# (`elem_value.is_a?(MacroTupleValue) && elem_value.elements.size >= 2`),
# so stage2 never took the `{% for k, v in hash %}` pair branch and dropped
# ~2.6k macro-generated primitive defs (Int#to_*, operators).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/and_rhs_is_a.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_and.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
abstract class MV
end
class Box
  def initialize(@n : Int32)
  end
  def size : Int32
    @n
  end
end
class Bag
  def size : Int32
    99
  end
end
class MTup < MV
  def initialize(@b : Box)
  end
  def elements : Box
    @b
  end
end
class MNum < MV
  def initialize(@v : Int32)
  end
  def v : Int32
    @v
  end
end
def val_and(ev : MV) : Bool
  ev.is_a?(MTup) && ev.elements.size >= 2
end
def cond_and(ev : MV) : Int32
  if ev.is_a?(MTup) && ev.elements.size >= 2
    1
  else
    0
  end
end
def chain_and(ev : MV) : Bool
  ev.is_a?(MTup) && ev.elements.size >= 2 && ev.elements.size < 10
end
def scoped(ev : MV) : Int32
  ok = ev.is_a?(MTup) && ev.elements.size >= 2
  return 7 if ok
  if ev.is_a?(MNum)
    ev.v
  else
    0
  end
end
t2 = MTup.new(Box.new(2)).as(MV)
t1 = MTup.new(Box.new(1)).as(MV)
t20 = MTup.new(Box.new(20)).as(MV)
n = MNum.new(5).as(MV)
LibC.exit(10) unless Bag.new.size == 99
LibC.exit(1) unless val_and(t2)
LibC.exit(2) if val_and(t1)
LibC.exit(3) if val_and(n)
LibC.exit(4) unless cond_and(t2) == 1
LibC.exit(5) unless cond_and(n) == 0
LibC.exit(6) unless chain_and(t2)
LibC.exit(7) if chain_and(t20)
LibC.exit(8) unless scoped(t2) == 7
LibC.exit(9) unless scoped(n) == 5
LibC.exit(0)
CR
cat >"$WORK_DIR/pl_and.cr" <<'CR'
abstract class MV
end
class MArr < MV
  getter elements : Array(MV)
  def initialize(@elements); end
end
class MTup < MV
  getter elements : Array(MV)
  def initialize(@elements); end
end
class MNum < MV
  getter v : Int32
  def initialize(@v); end
end
def a1(ev : MV)
  ev.is_a?(MTup) && ev.elements.size >= 2
end
t = MTup.new([MNum.new(1).as(MV), MNum.new(2).as(MV)]).as(MV)
STDERR.puts "a1=#{a1(t)}"
exit 1 unless a1(t)
exit 2 if a1(MNum.new(3).as(MV))
exit 0
CR
for name in np_and pl_and; do
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
echo and_rhs_is_a_narrowing_repro_ok
