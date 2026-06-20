# A' step (c) reducer: read-only per-type inline-value SAFE-SET probe.
#
# Run under ADAMAS_INLINE_VALUE_SAFE_SET_PROBE=1; the companion script greps the
# [SAFESET] lines and asserts the v1 safe-set rule  { C | bv && !vd && !erased_flow }:
#
#   Vec2 — exercised every which way: stored into / read from Array(Vec2) (push,
#          each, [], map) AND pushed through every erasure-attempt form — an
#          `Indexable(Vec2)` parameter, an `.as(Indexable(Vec2))` cast, and a
#          two-implementer abstract dispatch (a class that `include Indexable(Vec2)`
#          plus an Array(Vec2), both passed to one `Indexable(Vec2)` method).
#          This compiler MONOMORPHIZES all of them to the concrete `Array(Vec2)#…`
#          body, so every read stays a buffer_value access (bv=1), no raw-pointer
#          read (vd=0), and Array(Vec2) never flows into a type-erased body
#          (erased_flow=0) → SAFE. The erasure-attempt forms are what make the
#          erased_flow=0 result a durable test, not just a one-shot observation.
#
#   Vraw — also Array-stored, but ADDITIONALLY accessed through a standalone raw
#          Pointer(Vraw) that is NOT the Array @buffer chain — a value_derived
#          access on both the store (`ptr[i] = …`) and the load (`ptr[i]`) side
#          (vd=1) → UNSAFE (excluded from v1 inline-store).
#
# One compile proves both poles: the gate ADMITS a value struct that is only ever
# Array-resident (even under abstract dispatch) and EXCLUDES one with a raw-pointer
# (stride-aliasing) access path.
struct Vec2
  getter x : Int32
  getter y : Int32

  def initialize(@x : Int32, @y : Int32)
  end
end

struct Vraw
  getter a : Int32
  getter b : Int32

  def initialize(@a : Int32, @b : Int32)
  end
end

# A second Indexable(Vec2) implementer, so `sum_indexable` cannot be reduced to a
# single concrete receiver — dispatch is forced through the abstract interface.
class MyColl
  include Indexable(Vec2)

  def initialize
    @data = [] of Vec2
    @data << Vec2.new(7, 8)
  end

  def size : Int32
    @data.size
  end

  def unsafe_fetch(i : Int) : Vec2
    @data.unsafe_fetch(i)
  end
end

def sum_indexable(coll : Indexable(Vec2)) : Int32
  total = 0
  j = 0
  while j < coll.size
    total += coll.unsafe_fetch(j).x
    j += 1
  end
  total
end

# Vec2: concrete Array access (push, each, [], map).
av = [] of Vec2
i = 0
while i < 4
  av << Vec2.new(i, i + 1)
  i += 1
end
sum = 0
av.each do |v|
  sum += v.x + v.y
end
first = av[0]
doubled = av.map { |v| Vec2.new(v.x * 2, v.y * 2) }

# Vec2: erasure-attempt forms (all monomorphize to Array(Vec2)#… here).
casted = av.as(Indexable(Vec2))
erased_sum = sum_indexable(av) + sum_indexable(MyColl.new) + sum_indexable(casted)

# Vraw: Array-stored AND read/written via a standalone raw Pointer(Vraw).
rv = [] of Vraw
rv << Vraw.new(10, 20)
p = Pointer(Vraw).malloc(2_u64)
idx = 1
p[idx] = Vraw.new(30, 40)
got = p[idx]

STDERR.puts "first=#{first.x} sum=#{sum} d0=#{doubled[0].x} es=#{erased_sum} got=#{got.a + rv[0].b}"
STDOUT.flush
exit(0)
