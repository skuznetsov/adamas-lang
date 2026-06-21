# C-narrow-a CONSTRUCT-IN-PLACE invariant goldens (GPT review round 1, blocker 3).
#
# These pin the LEGACY (gate-OFF) runtime behavior that the FUTURE C-narrow-a
# placement rewrite (construct the ctor directly in @buffer[size]) MUST preserve.
# Construct-in-place can corrupt Array invariants even with correct POD/storage
# gates, so each invariant gets an observable falsifier:
#   (1) ctor args evaluated ONCE and in Crystal source order;
#   (2) capacity grown BEFORE slot writes and size incremented only AFTER full slot
#       init — observed indirectly: after many grows/reallocs every element is intact;
#   (3) partial init invisible on raise — a ctor raising mid-construction must NOT
#       add a partial element nor advance size (V2 supports raise-in-ctor + rescue,
#       verified, so this is a REAL falsifier, not vacuous).
struct V3
  getter a : Int32
  getter b : Int32
  getter c : Int32

  def initialize(@a : Int32, @b : Int32, @c : Int32)
    raise "boom" if @a == 99
  end
end

module Trace
  @@order = [] of Int32

  def self.tap(n : Int32) : Int32
    @@order << n
    n
  end

  def self.order : Array(Int32)
    @@order
  end
end

# (1) args evaluated ONCE and in source order.
arr = [] of V3
arr << V3.new(Trace.tap(1), Trace.tap(2), Trace.tap(3))
order_ok = (Trace.order == [1, 2, 3]) && (arr[0].a == 1 && arr[0].b == 2 && arr[0].c == 3)

# (2) grow/realloc preserves every element (capacity-before-write + size-after-init).
g = [] of V3
i = 0
while i < 50
  g << V3.new(i, i * 2, i * 3)
  i += 1
end
contents_ok = true
j = 0
while j < g.size
  v = g[j]
  contents_ok = false unless v.a == j && v.b == j * 2 && v.c == j * 3
  j += 1
end
grow_ok = (g.size == 50) && contents_ok

# (3) partial init invisible on raise.
p = [] of V3
p << V3.new(5, 5, 5)
raised = false
begin
  p << V3.new(99, 0, 0)
rescue ex
  raised = true
end
partial_ok = raised && (p.size == 1) && (p[0].a == 5)

STDERR.puts "RESULT order_ok=#{order_ok} grow_ok=#{grow_ok} partial_ok=#{partial_ok} order=#{Trace.order} gsize=#{g.size}"
STDERR.flush
exit(0)
