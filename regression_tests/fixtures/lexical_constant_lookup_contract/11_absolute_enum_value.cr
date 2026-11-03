lib LibC
  fun putchar(value : Int32) : Int32
end

enum RootedColor : Int32
  Amber = 65
end

::RootedColor::Amber
LibC.putchar(65)
LibC.putchar(10)
