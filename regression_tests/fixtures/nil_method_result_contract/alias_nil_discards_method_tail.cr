@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
end
alias Nothing = Nil
def result : Nothing
  LibC.putchar(65)
  65
end
def emit(value : Nil)
  LibC.putchar(78)
end
emit(result)
LibC.putchar(10)
