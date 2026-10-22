lib DeclaredTypes
  fun unused(callback : ForwardCallback) : Void
  fun putchar(value : Int32) : Int32
end
alias ForwardCallback = Int32 -> Int32
DeclaredTypes.putchar(65_i32)
DeclaredTypes.putchar(10_i32)
