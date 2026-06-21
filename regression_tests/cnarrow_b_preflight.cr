# C-narrow-b PREFLIGHT eligibility reducer (gate ADAMAS_CNARROW_B_PREFLIGHT, needs A').
#
# The read-only preflight classifies each inline-C `ArrayGet` by the brutally-narrow v1
# (same-block local field reads only; no call/Array-mutation/alias/escape) and marks the
# eligible ones. This .cr wires V3 into one positive + four carrier-required negatives:
#   POSITIVE  : `v = arr[j]; sum += v.a + v.b + v.c`     -> eligible (same-block field reads)
#   recv_borrow: `arr[k].total`                           -> call    (load used as receiver)
#   stored    : `sink << arr[2]`                          -> call    (loaded value pushed away)
#   returned  : `first_elem(arr)` returns `arr[0]`        -> returned
#   intervening: `v2 = arr[0]; arr << V3.new(..); v2.a`   -> intervening_call
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

def first_elem(arr : Array(V3)) : V3
  arr[0] # returned -> carrier
end

arr = [] of V3
i = 0
while i < 8
  arr << V3.new(i, i * 2, i * 3)
  i += 1
end

# POSITIVE: same-block local field reads.
sum = 0
j = 0
while j < arr.size
  v = arr[j]
  sum += v.a + v.b + v.c
  j += 1
end

# NEGATIVE recv_borrow: loaded value used as a method receiver.
rb = 0
k = 0
while k < arr.size
  rb += arr[k].total
  k += 1
end

# NEGATIVE stored: loaded value pushed into another container.
sink = [] of V3
sink << arr[2]

# NEGATIVE returned.
ret = first_elem(arr)

# NEGATIVE intervening: a push (call) between the load and its field use.
v2 = arr[0]
arr << V3.new(9, 9, 9)
acc = v2.a

STDERR.puts "sum=#{sum} rb=#{rb} sink=#{sink.size} ret=#{ret.a} acc=#{acc}"
STDOUT.flush
exit(0)
