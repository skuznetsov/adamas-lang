@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
def choose(left : Int32.class, right : Int32) : Int32
  65
end
def choose(left : Int32, right : Int32.class) : Int32
  88
end
C.putchar(choose(right: 1, left: Int32))
C.putchar(10)
