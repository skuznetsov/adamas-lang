lib LibC
  fun putchar(value : Int32) : Int32
end
macro choose(value)
  LibC.putchar(65)
end
macro choose(value, extra = nil)
  LibC.putchar(66)
end
macro choose(replacement)
  LibC.putchar(67)
end
choose(1)
choose(1, 2)
LibC.putchar(10)
