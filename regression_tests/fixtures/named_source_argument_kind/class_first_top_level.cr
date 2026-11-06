@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
def choose(value : Int32.class) : Int32
  65
end
def choose(value : Int32) : Int32
  88
end
C.putchar(choose(value: Int32))
C.putchar(10)
