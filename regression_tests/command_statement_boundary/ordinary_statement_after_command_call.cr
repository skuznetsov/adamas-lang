lib LibC
  fun putchar(value : Int32) : Int32
end

def identity(value : Int32) : Int32
  value
end

first = identity 65
second = 66
LibC.putchar(first)
LibC.putchar(second)
