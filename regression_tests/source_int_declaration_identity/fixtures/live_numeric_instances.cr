lib C
  fun putchar(value : Int32) : Int32
end
def choose(value : Int32)
  C.putchar(72)
end
def choose(value : Int)
  if value == 4294967297_i64
    C.putchar(73)
  else
    C.putchar(74)
  end
end
choose(1_i32)
choose(4294967297_i64)
choose(7_u64)
