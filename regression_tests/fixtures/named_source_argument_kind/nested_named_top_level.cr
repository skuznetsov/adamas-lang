@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
def choose(value : Int32) : Int32
  88
end
def choose(value : Int32.class) : Int32
  65
end
def invoke : Int32
  choose(value: Int32)
end
C.putchar(invoke())
C.putchar(10)
