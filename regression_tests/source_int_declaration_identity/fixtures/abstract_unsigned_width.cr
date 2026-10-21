lib C
  fun putchar(value : Int32) : Int32
end
def choose(value : Int32)
  C.putchar(88)
end
def choose(value : Int)
  if value == 18446744073709551615_u64
    C.putchar(71)
  else
    C.putchar(89)
  end
end
choose(18446744073709551615_u64)
