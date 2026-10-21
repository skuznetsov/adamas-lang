lib LibC
  fun putchar(value : Int32) : Int32
end

class Earlier
  class Parent
  end
end
module Destination
  class Child < Earlier::Parent
  end
end
LibC.putchar(65_i32)
