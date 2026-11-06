lib LibC
  fun putchar(value : Int32) : Int32
end
macro choose(value, *rest)
  LibC.putchar(65)
end
macro choose(value)
  LibC.putchar(66)
end
choose(1)
LibC.putchar(10)
