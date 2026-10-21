lib LibC
  fun putchar(value : Int32) : Int32
end

def value(argument : Int32)
  argument
end
input = 67_i32
LibC.putchar(value(input))
