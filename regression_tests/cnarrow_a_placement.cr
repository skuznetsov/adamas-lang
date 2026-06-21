# C-narrow-a PLACEMENT behavior reducer.
# A clean Array(V3) push loop + readback. Under A' only, `arr << V3.new(..)` heap-
# allocates a transient V3 (the push memcpy's it inline). Under A' + placement the
# transient becomes a STACK alloc at the callsite (0 heap alloc), behavior-identical.
struct V3
  getter a : Int32
  getter b : Int32
  getter c : Int32

  def initialize(@a : Int32, @b : Int32, @c : Int32)
  end
end

arr = [] of V3
i = 0
while i < 16
  arr << V3.new(i, i * 2, i * 3)
  i += 1
end
sum = 0
j = 0
while j < arr.size
  v = arr[j]
  sum += v.a + v.b + v.c
  j += 1
end
STDERR.puts "RESULT sum=#{sum} size=#{arr.size}"
STDOUT.flush
exit(0)
