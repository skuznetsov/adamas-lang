lib C
  fun putchar(value : Int32) : Int32
end
def choose(value : Int)
  missing_unused_broad_body
end
def choose(value : Int32)
  C.putchar(66)
end
choose(1_i32)
