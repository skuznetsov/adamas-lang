# A' provenance-marker reducer: POSITIVE Array(Vec2) inline-buffer access must be
# categorized as `buffer_value` (the A' mark set), while a NEGATIVE raw
# Pointer(Vec2) indexed access (NOT an Array buffer) must NOT land in buffer_value
# — it has no `Load(static GEP @buffer of Array self)` provenance chain.
#
# Run under ADAMAS_ARRAY_BUFFER_PROVENANCE_PROBE=1; the companion shell script
# asserts the categorization and the 0-marks-outside-Array invariant.
struct Vec2
  getter x : Int32
  getter y : Int32

  def initialize(@x : Int32, @y : Int32)
  end

  def sum : Int32
    @x + @y
  end
end

# POSITIVE: monomorphic Array(Vec2) inline buffer store (#push) + load (#unsafe_fetch).
av = [] of Vec2
i = 0
while i < 8
  av << Vec2.new(i, i * 2)
  i += 1
end
first = av[0]
total = first.sum

# NEGATIVE: a raw Pointer(Vec2) indexed via a runtime index → GetElementPtrDynamic
# over Vec2 whose base is the malloc result, NOT Load(GEP @buffer of an Array self).
# This must NOT be marked buffer_value (it is value_derived / neither).
ptr = Pointer(Vec2).malloc(4_u64)
idx = 2
ptr[idx] = Vec2.new(100, 200)
got = ptr[idx]
total += got.sum

STDERR.puts "total=#{total}"
STDOUT.flush
exit(0)
