lib LibC
  fun putchar(value : Int32) : Int32
end
macro choose(value, *, flag)
  LibC.putchar(65)
end
macro choose(value)
  LibC.putchar(66)
end
choose(1, flag: 2)
choose(1)
LibC.putchar(10)
