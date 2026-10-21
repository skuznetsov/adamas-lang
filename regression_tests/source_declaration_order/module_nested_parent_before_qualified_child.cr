lib LibC
  fun putchar(value : Int32) : Int32
end

module Earlier
  class Parent
  end
end
class Destination
end
class Destination::Child < Earlier::Parent
end
LibC.putchar(65_i32)
