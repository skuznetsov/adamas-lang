lib LibC
  fun putchar(value : Int32) : Int32
end
def raise : Int32
  LibC.putchar(65)
  65
end
raise
LibC.putchar(10)
