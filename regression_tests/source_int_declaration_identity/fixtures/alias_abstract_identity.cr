lib C
  fun putchar(value : Int32) : Int32
end
alias Integral = Int
alias AnyIntegral = Integral
def choose(value : Int32)
  C.putchar(67)
end
def choose(value : AnyIntegral)
  missing_unused_broad_body
end
choose(1_i32)
