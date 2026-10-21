lib LibC
  fun putchar(value : Int32) : Int32
end

class PriorParent
end
require "./dependencies/prior_child"
LibC.putchar(65_i32)
