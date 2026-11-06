@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
def emit(value : Int32, *rest)
  C.putchar(value)
end
emit(67, *{2, 3})
C.putchar(10)
