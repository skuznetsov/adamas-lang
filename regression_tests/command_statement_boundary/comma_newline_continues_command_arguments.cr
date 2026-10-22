lib LibC
  fun putchar(value : Int32) : Int32
end

def second(first : Int32, last : Int32) : Int32
  last
end

value = second 0,
  70
LibC.putchar(value)
