# Stock-first oracle for the StaticArray(C-struct) storage contract.
#
# A 32-byte C element must occupy 32 bytes in the StaticArray, both when
# indexing the array and when using its address as Pointer(T). The output bits
# expose copy and receiver behavior without assuming which one stock Crystal
# uses for `values[0].field = ...`.
require "pointer"

lib StaticArrayProbe
  struct Block
    head : UInt64
    middle : UInt64
    tail : UInt64
    stamp : UInt64
  end

  fun putchar(value : Int32) : Int32
end

def emit_bit(value : Bool)
  StaticArrayProbe.putchar(value ? 49 : 48)
end

values = uninitialized StaticArrayProbe::Block[2]
base = pointerof(values).as(StaticArrayProbe::Block*)

first = uninitialized StaticArrayProbe::Block
first.head = 11_u64
first.middle = 12_u64
first.tail = 13_u64
first.stamp = 14_u64

second = uninitialized StaticArrayProbe::Block
second.head = 21_u64
second.middle = 22_u64
second.tail = 23_u64
second.stamp = 24_u64

# Raw Pointer(T) stores are byte copies at the 32-byte C layout stride.
base.value = first
(base + 1).value = second
emit_bit(values[0].head == 11_u64 && values[0].stamp == 14_u64)
emit_bit(values[1].head == 21_u64 && values[1].middle == 22_u64 && values[1].stamp == 24_u64)
emit_bit((base + 1).value.tail == 23_u64)

# StaticArray IndexSet must copy all 32 bytes. IndexGet must return a value
# whose later mutation is independent of the source element.
values[0] = second
emit_bit(values[0].head == 21_u64 && values[0].stamp == 24_u64)
copy = values[0]
copy.head = 91_u64
emit_bit(copy.head == 91_u64)
emit_bit(values[0].head == 21_u64)

# Keep this receiver mutation observational: compare stock and candidate output
# to establish whether StaticArray indexing borrows the slot for field setters.
values[0].head = 31_u64
emit_bit(values[0].head == 31_u64)

StaticArrayProbe.putchar(10)
