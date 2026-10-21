lib C
  fun putchar(value : Int32) : Int32
end
def choose(value : Int32)
  C.putchar(false)
end
def choose(value : Int)
  C.putchar(88)
end
choose(1_i32)
