# EXPECT: layout_ok
# Tests that nilable struct fields in classes have correct sizes.
# V2 must treat Nil|Struct unions as tagged unions (not nullable pointers)
# because V2 structs lack runtime type headers.

struct LargeSpan
  getter a : Int32
  getter b : Int32
  getter c : Int32
  getter d : Int32
  getter e : Int32
  getter f : Int32
  def initialize(@a : Int32, @b : Int32, @c : Int32, @d : Int32, @e : Int32, @f : Int32)
  end
end

class NodeWithNilableStructs
  getter span : LargeSpan
  getter name : Slice(UInt8)
  getter data : Array(Int32)?
  getter optional_slice : Slice(UInt8)?
  getter body : Array(Int32)?
  getter flag : Bool?
  getter receiver : Slice(UInt8)?

  def initialize(@span, @name, @data, @optional_slice, @body, @flag, @receiver)
  end
end

# Create with non-nil values for nilable struct fields
node = NodeWithNilableStructs.new(
  LargeSpan.new(10, 20, 30, 40, 50, 60),
  "hello".to_slice,
  [1, 2, 3],
  "world".to_slice,
  [4, 5, 6],
  true,
  "test!".to_slice
)

# Verify all fields are readable and correct
ok = true
ok = false unless node.span.a == 10
ok = false unless node.span.f == 60
ok = false unless node.name.size == 5
ok = false unless node.data.try(&.size) == 3
ok = false unless node.optional_slice.try(&.size) == 5
ok = false unless node.body.try(&.size) == 3
ok = false unless node.flag == true
ok = false unless node.receiver.try(&.size) == 5

# Create with nil values
node2 = NodeWithNilableStructs.new(
  LargeSpan.new(1, 2, 3, 4, 5, 6),
  "x".to_slice,
  nil,
  nil,
  nil,
  nil,
  nil
)
ok = false unless node2.optional_slice.nil?
ok = false unless node2.body.nil?
ok = false unless node2.flag.nil?
ok = false unless node2.receiver.nil?

puts ok ? "layout_ok" : "LAYOUT_BUG"
