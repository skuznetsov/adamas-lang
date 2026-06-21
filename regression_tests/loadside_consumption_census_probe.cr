# Load-side consumption census VALIDATION probe.
# Exercises all four verdict classes for one leaf-POD struct V3 so we can confirm
# the classifier buckets them correctly (fail-closed):
#   (1) stack_local : loaded value's fields read locally, value never escapes.
#   (2) recv_borrow : loaded value passed in RECEIVER position to a method.
#   (3) heap:stored : loaded value stored into another container.
#   (4) heap:returned : loaded value returned from a function.
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
  arr[0] # (4) loaded result is RETURNED -> heap:returned
end

arr = [] of V3
i = 0
while i < 8
  arr << V3.new(i, i * 2, i * 3)
  i += 1
end

# (1) stack_local: read fields of the loaded value locally.
acc = 0
j = 0
while j < arr.size
  v = arr[j]
  acc += v.a + v.b + v.c
  j += 1
end

# (2) recv_borrow: loaded value used as the receiver of a method call.
borrow_acc = 0
k = 0
while k < arr.size
  borrow_acc += arr[k].total
  k += 1
end

# (3) heap:stored: loaded value stored into another container.
sink = [] of V3
sink << arr[2]

# (4) heap:returned via first_elem.
ret = first_elem(arr)

STDERR.puts "acc=#{acc} borrow=#{borrow_acc} sink=#{sink.size} ret=#{ret.a}"
STDERR.flush
exit(0)
