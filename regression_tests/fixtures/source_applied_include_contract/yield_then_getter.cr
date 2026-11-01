require "object/properties"
class ShapeOwner
  def initialize(@value : Int32)
  end
  def value : Int32
    yield 66
  end
  getter value : Int32
end
lib C
  fun putchar(value : Int32) : Int32
end
C.putchar(ShapeOwner.new(65).value)
C.putchar(ShapeOwner.new(65).value { |x| x })
C.putchar(10)
