lib C
  fun putchar(value : Int32) : Int32
end
def choose(value : Int32)
  C.putchar(88)
end
def choose(value : Int)
  C.putchar(false)
end
choose(4294967297_i64)
