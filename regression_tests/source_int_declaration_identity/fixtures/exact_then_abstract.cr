lib C
  fun putchar(value : Int32) : Int32
end
def choose(value : Int32)
  C.putchar(65)
end
def choose(value : Int)
  missing_unused_broad_body
end
choose(1_i32)
