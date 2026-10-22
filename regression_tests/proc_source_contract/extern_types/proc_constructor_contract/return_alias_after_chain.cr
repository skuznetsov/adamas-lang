lib LateReturnAliasRuntime
  fun putchar(value : LateWord) : LateReturn
end
alias LateWord = Int32
alias LateReturnLeaf = Int32
alias LateReturn = LateReturnLeaf
LateReturnAliasRuntime.putchar(69_i32)
LateReturnAliasRuntime.putchar(10_i32)
