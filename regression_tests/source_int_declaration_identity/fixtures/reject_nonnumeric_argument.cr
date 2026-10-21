lib C
  fun putchar(value : Int32) : Int32
end
def choose(value : Int32)
  C.putchar(88)
end
def choose(value : Int)
  C.putchar(89)
end
choose(false)
