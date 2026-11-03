lib LibC
  fun putchar(value : Int32) : Int32
end
module DefaultedOverload
  def self.value(seed : Int32, *, payload : Int32 = 0_i32) : Int32
    65_i32
  end
  def self.value(seed : Int64, *, payload : Int64 = 0_i64) : Int32
    66_i32
  end
  def self.value(seed : Int32, other : Int32) : Int32
    88_i32
  end
end
LibC.putchar(DefaultedOverload.value(1_i32))
LibC.putchar(DefaultedOverload.value(1_i64))
LibC.putchar(DefaultedOverload.value(1_i32, 2_i32))
