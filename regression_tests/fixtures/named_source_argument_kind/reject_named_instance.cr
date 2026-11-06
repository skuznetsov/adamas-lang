@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
def only_class(value : Int32.class) : Int32
  65
end
C.putchar(only_class(value: 1))
