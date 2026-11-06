lib LibC
  fun putchar(value : Int32) : Int32
end
macro need(value)
  LibC.putchar(65)
end
need(1, unknown: 2)
