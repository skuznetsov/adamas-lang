require "object/properties"
class ShapeOwner
  def initialize(@value : Int32)
  end
  getter value : Int32
  def value(*args : Int32) : Int32
    66
  end
end
lib C
  fun putchar(value : Int32) : Int32
end
C.putchar(ShapeOwner.new(65).value)
C.putchar(ShapeOwner.new(65).value(1))
C.putchar(10)
