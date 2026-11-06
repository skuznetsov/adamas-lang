lib LibC
  fun putchar(value : Int32) : Int32
end
macro string_only
  {{ "LibC.putchar())" }}
end
string_only
LibC.putchar(65)
LibC.putchar(10)
