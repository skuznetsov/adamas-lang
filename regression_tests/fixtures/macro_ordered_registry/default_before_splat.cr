lib LibC
  fun putchar(value : Int32) : Int32
end
macro probe(required, fallback = 65, *rest)
  67
end
LibC.putchar(probe())
LibC.putchar(10)
