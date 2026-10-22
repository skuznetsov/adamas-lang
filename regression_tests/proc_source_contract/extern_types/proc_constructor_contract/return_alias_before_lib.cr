alias EarlyWord = Int32
alias EarlyReturn = EarlyWord
lib EarlyReturnAliasRuntime
  fun putchar(value : EarlyWord) : EarlyReturn
end
EarlyReturnAliasRuntime.putchar(68_i32)
EarlyReturnAliasRuntime.putchar(10_i32)
