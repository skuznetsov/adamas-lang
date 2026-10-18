lib LibC
  fun putchar(value : Int32) : Int32
end
def raise(value : Int32) : Int32
  LibC.putchar(value)
  value
end
raise 65
LibC.putchar(10)
