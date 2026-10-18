lib LibC
  fun putchar(c : Int32) : Int32
end

def mark(code : Int32, value : Int32) : Int32
  LibC.putchar(code)
  value
end

def bind(*, first : Int32 = mark(68, 65), second : Int32)
  LibC.putchar(66)
  LibC.putchar(first)
  LibC.putchar(second)
end

bind(second: mark(86, 90))
LibC.putchar(10)
