# C-narrow-b BEHAVIOR reducer (gates ADAMAS_CNARROW_B_LOAD + ADAMAS_INLINE_VALUE_ARRAY_STORAGE).
# An eligible same-block local-field-read V3 load gets a DIRECT slot read (no A' heap
# carrier); a recv_borrow V3 load keeps the carrier. Behavior must be identical.
struct V3
  getter a : Int32
  getter b : Int32
  getter c : Int32

  def initialize(@a : Int32, @b : Int32, @c : Int32)
  end

  def total : Int32
    @a + @b + @c
  end
end

arr = [] of V3
i = 0
while i < 1000
  arr << V3.new(i, i * 2, i * 3)
  i += 1
end

# ELIGIBLE: same-block local field reads -> direct slot (carrier eliminated).
sum = 0_i64
j = 0
while j < arr.size
  v = arr[j]
  sum = sum &+ (v.a &+ v.b &+ v.c).to_i64
  j += 1
end

# NEGATIVE: recv_borrow (arr[k] used as receiver) -> carrier kept.
rb = 0_i64
k = 0
while k < arr.size
  rb = rb &+ arr[k].total.to_i64
  k += 1
end

STDERR.puts "RESULT sum=#{sum} rb=#{rb} size=#{arr.size}"
STDOUT.flush
exit(0)
