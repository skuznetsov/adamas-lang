lib LibC
  fun putchar(value : Int32) : Int32
end
macro choose(*, first)
  LibC.putchar(65)
end
macro choose(*, second)
  LibC.putchar(66)
end
choose(first: 1)
choose(second: 2)
LibC.putchar(10)
