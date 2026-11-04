lib LibC
  fun putchar(value : Int32) : Int32
end
enum Tone
  Red
end
def choose(value : Tone) : Int32
  65
end
def choose(*items, suffix : Int32 = 66) : Int32
  suffix
end
LibC.putchar(choose(:red))
LibC.putchar(10)
