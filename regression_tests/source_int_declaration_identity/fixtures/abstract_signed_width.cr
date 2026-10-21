lib C
  fun putchar(value : Int32) : Int32
end
def choose(value : Int32)
  C.putchar(88)
end
def choose(value : Int)
  if value == 4294967297_i64
    C.putchar(70)
  else
    C.putchar(89)
  end
end
choose(4294967297_i64)
