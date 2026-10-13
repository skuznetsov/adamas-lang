#!/usr/bin/env bash
# Control-flow merges (if/elsif, case, begin/rescue, inlined yield returns) whose
# branches produce DIFFERENT numeric primitive types kept the first branch's
# type as the phi type and value-cast the rest (`if c; 2; else; 2.5; end` became
# Int32 with 2.5 truncated). Crystal types such a merge as the union of branch
# types (Int32 | Float64), preserving each payload and its runtime variant.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/numeric_branch_merge.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_merge.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def a2(k : Int32) : Int32 | Float64
  if k == 0
    2
  else
    2.5
  end
end

def a3(k : Int32) : Int32 | Int64 | Float64
  if k == 0
    2
  elsif k == 1
    5_i64
  else
    2.5
  end
end

def b3(k : Int32)
  if k == 0
    2
  elsif k == 1
    5_i64
  else
    2.5
  end
end

def cs(k : Int32)
  case k
  when 0 then 7
  else        7.25
  end
end

def yl(k : Int32)
  yield k
end

def via_yield(k : Int32)
  yl(k) { |x| x == 0 ? 3 : 3.5 }
end

def via_if_yield(k : Int32)
  yl(k) do |x|
    if x == 0
      4
    else
      4.5
    end
  end
end

r = 0
r |= 1 unless a2(1).is_a?(Float64) && a2(0).is_a?(Int32)
r |= 2 unless a3(2).is_a?(Float64) && a3(1).is_a?(Int64) && a3(0).is_a?(Int32)
r |= 4 unless b3(2).is_a?(Float64) && b3(1).is_a?(Int64)
v = b3(2)
r |= 8 unless v.is_a?(Float64) && v == 2.5
r |= 16 unless cs(1).is_a?(Float64) && cs(0).is_a?(Int32)
w = via_if_yield(1)
r |= 32 unless w.is_a?(Float64) && w == 4.5
u = via_yield(1)
r |= 64 unless u.is_a?(Float64) && u == 3.5
LibC.exit(r)
CR
cat >"$WORK_DIR/merge.cr" <<'CR'
def f(k : Int32)
  if k == 0
    1
  else
    1.75
  end
end

def g(k : Int32)
  begin
    raise "x" if k == 1
    10
  rescue
    10.5
  end
end

r = 0
x = f(1)
r |= 1 unless x.is_a?(Float64) && x == 1.75
y = f(0)
r |= 2 unless y.is_a?(Int32) && y == 1
z = g(1)
r |= 4 unless z.is_a?(Float64) && z == 10.5
exit r
CR
for name in np_merge merge; do
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
echo numeric_branch_merge_union_repro_ok
