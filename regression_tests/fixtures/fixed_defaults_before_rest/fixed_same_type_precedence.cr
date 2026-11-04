lib LibC
  fun putchar(value : Int32) : Int32
end

def pick(a : Int32, b : Int32) : Int32
  LibC.putchar(65)
  0
end

def pick(a : Int32, *rest : Int32, suffix : Int32 = 90) : Int32
  LibC.putchar(66)
  0
end

pick(70, 71)
LibC.putchar(10)
