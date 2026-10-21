lib LibC
  fun putchar(value : Int32) : Int32
end

LibC.putchar(65_i32)
require "./dependencies/cycle_b"
LibC.putchar(67_i32)
