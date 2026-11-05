struct UInt64
  @[Primitive(:binary)]
  def ==(other : UInt64) : Bool
  end
end

lib AllocateRecordProbe
  fun exit(status : Int32) : NoReturn
  fun putchar(value : Int32) : Int32
end

struct Leaf16
  def left : UInt64
    @left
  end

  def right : UInt64
    @right
  end

  def initialize(@left : UInt64, @right : UInt64)
  end
end

struct Nested24
  def leaf : Leaf16
    @leaf
  end

  def tail : UInt64
    @tail
  end

  def initialize(@leaf : Leaf16, @tail : UInt64)
  end
end

# Range literals lower to Allocate(begin, end, exclusive). This local
# declaration supplies the final registered record layout without a prelude.
struct Range(B, E)
  @begin : B
  @end : E
  @exclusive : Bool

  def initialize(@begin : B, @end : E, @exclusive : Bool = false)
  end

  def start_value : B
    @begin
  end

  def exclusive? : Bool
    @exclusive
  end
end

leaf = Leaf16.new(0x1122334455667788_u64, 0x7766554433221100_u64)
leaf_range = leaf..nil
AllocateRecordProbe.exit(11) unless leaf_range.start_value.left == 0x1122334455667788_u64
AllocateRecordProbe.exit(12) unless leaf_range.start_value.right == 0x7766554433221100_u64
AllocateRecordProbe.exit(13) if leaf_range.exclusive?

nested = Nested24.new(leaf, 0xAABBCCDDEEFF0011_u64)
nested_range = nested...nil
AllocateRecordProbe.exit(14) unless nested_range.start_value.leaf.left == 0x1122334455667788_u64
AllocateRecordProbe.exit(15) unless nested_range.start_value.leaf.right == 0x7766554433221100_u64
AllocateRecordProbe.exit(16) unless nested_range.start_value.tail == 0xAABBCCDDEEFF0011_u64
AllocateRecordProbe.exit(17) unless nested_range.exclusive?

AllocateRecordProbe.putchar(65)
AllocateRecordProbe.putchar(10)
