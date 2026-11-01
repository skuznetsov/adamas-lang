require "object/properties"
class ShapeOwner
  def initialize(@value : Int32)
  end
  def value(*args : Int32) : Int32
    66
  end
  getter value : Int32
end
lib C
  fun putchar(value : Int32) : Int32
end
C.putchar(ShapeOwner.new(65).value)
C.putchar(ShapeOwner.new(65).value(1))
C.putchar(10)
