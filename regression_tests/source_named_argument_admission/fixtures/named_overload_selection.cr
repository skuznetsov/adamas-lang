lib LibC
  fun putchar(c : Int32) : Int32
end

def pick(*, value : Int32, pad : Int32 = 0) : Int32
  73
end

def pick(*, value : String, pad : Int32 = 0) : Int32
  83
end

LibC.putchar(pick(value: 7))
LibC.putchar(pick(pad: 2, value: "seven"))
LibC.putchar(10)
