lib LibC
  fun putchar(c : Int32) : Int32
end
macro emit
  LibC.putchar({{ 65 }})
end
emit
LibC.putchar(10)
