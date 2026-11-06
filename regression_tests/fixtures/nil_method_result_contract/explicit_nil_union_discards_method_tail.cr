@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
end
def result : Nil | Nil
  LibC.putchar(65)
  65
end
def emit(value : Nil)
  LibC.putchar(78)
end
emit(result)
LibC.putchar(10)
