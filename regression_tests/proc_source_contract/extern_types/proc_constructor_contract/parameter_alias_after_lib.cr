lib DeclaredTypes
  fun consume = putchar(value : ForwardArg) : Int32
end
alias ForwardArg = Int32
DeclaredTypes.consume(65_i32)
DeclaredTypes.consume(10_i32)
