lib LibC
  fun putchar(value : Int32) : Int32
end
def choose(value : Int32) : Int32
  65
end
def choose(*items, suffix : Int32 = 66) : Int32
  suffix
end
LibC.putchar(choose(99))
LibC.putchar(choose())
LibC.putchar(choose(1, 2))
LibC.putchar(10)
