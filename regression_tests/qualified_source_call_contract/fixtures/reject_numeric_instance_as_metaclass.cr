lib LibC
  fun putchar(c : Int32) : Int32
end
abstract struct Int
  def self.leaf_read(value : Int32, extra : Bool) : self
    self.leaf_zero
  end
end
struct UInt32
  def self.leaf_zero : UInt32
    65_u32
  end
end
struct UInt64
  def self.leaf_zero : UInt64
    66_u64
  end
end
def read_type(type)
  type.leaf_read(1_i32, true)
end
read_type(65_u32)
