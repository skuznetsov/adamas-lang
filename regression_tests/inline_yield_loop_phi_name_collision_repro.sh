#!/usr/bin/env bash
# Nested inline yields where the callee's loop counter and a caller-frame local
# share a name (`inner` loops `i` while `outer`'s block does `i += 1`). The
# name-keyed while-loop phi covered only the ctx-resolved callee `i`; the
# caller-frame `i` assigned inside the yield block got no header phi/backedge,
# so every iteration read its pre-loop value (Slice#each_with_index index stuck
# at 0 in stage2 => STUB CALLED ENV.forall).
# Two companion roots: (1) block-owner frame resolution matched nested inlines
# of top-level defs by function id ascending and picked the outermost frame;
# the owning frame index is now recorded at push time. (2) Snapshots and phi
# lookups inside an inlined block body filtered by the callee's local names,
# dropping a caller `i` at `break` (count_break returned 11 instead of 12).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inline_yield_loop_phi.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_nested.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def inner(&)
  i = 0
  while i < 3
    yield i
    i += 1
  end
end

def inner_next(&)
  i = 0
  while i < 4
    i += 1
    next if i == 2
    yield i
  end
end

def outer(&)
  i = 10
  inner do |x|
    yield x, i
    i += 1
  end
end

def outer_next(&)
  i = 100
  inner_next do |x|
    yield x, i
    i += 1
  end
end

def sum_idx : Int32
  acc = 0
  outer do |x, i|
    acc += i
  end
  acc
end

def sum_next : Int32
  acc = 0
  outer_next do |x, i|
    acc += i
  end
  acc
end

def count_after : Int32
  i = 10
  inner { |x| i += 1 }
  i
end

def count_break : Int32
  i = 10
  inner do |x|
    i += 1
    break if x == 1
  end
  i
end

r = 0
r |= 1 unless sum_idx == 33
r |= 2 unless sum_next == 303
r |= 4 unless count_after == 13
r |= 8 unless count_break == 12
LibC.exit(r)
CR
cat >"$WORK_DIR/np_module.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module MyEnum(T)
  abstract def each(& : T ->)

  def ewi(offset = 0, &)
    i = offset
    each do |elem|
      yield elem, i
      i += 1
    end
  end
end

module MyIdx(T)
  include MyEnum(T)

  def each(& : T ->)
    each_index do |i|
      yield unsafe_fetch(i)
    end
  end

  def each_index(& : Int32 ->) : Nil
    i = 0
    while i < size
      yield i
      i += 1
    end
  end
end

struct Sl(T)
  include MyIdx(T)

  def initialize(@p : Pointer(T), @size : Int32)
  end

  def size
    @size
  end

  def unsafe_fetch(i : Int)
    @p[i]
  end
end

def sum_idx(s : Sl(UInt8)) : Int32
  acc = 0
  s.ewi do |b, i|
    acc += i
  end
  acc
end

def early(s : Sl(UInt8), q : Pointer(UInt8)) : Bool
  s.ewi do |b, i|
    return false if b != q[i]
  end
  true
end

a = Pointer(UInt8).malloc(4)
a[0] = 1_u8; a[1] = 2_u8; a[2] = 3_u8
s = Sl(UInt8).new(a, 3)
r = 0
r |= 1 unless sum_idx(s) == 3
r |= 2 unless early(s, a)
LibC.exit(r)
CR
cat >"$WORK_DIR/slice_ewi.cr" <<'CR'
def b1(slice : Slice(UInt8)) : Int32
  acc = 0
  slice.each_with_index do |byte, i|
    acc += i
  end
  acc
end

def b2(slice : Slice(UInt8)) : Bool
  slice.each_with_index do |byte, i|
    return false if i > 100
  end
  true
end

def b3(slice : Slice(UInt8)) : Bool
  "abc".to_slice.each_with_index do |byte, i|
    return false if byte != slice[i]
  end
  true
end

s = "abc".to_slice
r = 0
r |= 1 unless b1(s) == 3
r |= 2 unless b2(s)
r |= 4 unless b3(s)
exit r
CR
for name in np_nested np_module slice_ewi; do
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
echo inline_yield_loop_phi_name_collision_repro_ok
