lib LibC
  fun putchar(value : Int32) : Int32
end

callback = -> { 1 }
LibC.putchar(65_i32)
LibC.putchar(10_i32)
