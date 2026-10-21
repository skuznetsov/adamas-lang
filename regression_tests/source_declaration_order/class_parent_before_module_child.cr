lib LibC
  fun putchar(value : Int32) : Int32
end

class EarlierParent
end
module Destination
  class Child < EarlierParent
  end
end
LibC.putchar(65_i32)
