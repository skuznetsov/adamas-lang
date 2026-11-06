lib LibC
  fun putchar(value : Int32) : Int32
end
macro need(value, *, flag)
  LibC.putchar(65)
end
need(1)
