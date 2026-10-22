require "proc"
lib LateExitAliasRuntime
  fun exit(status : Int32) : LateExitResult
end
alias LateExitLeaf = NoReturn
alias LateExitResult = LateExitLeaf
lib AliasOrderOutput
  fun putchar(value : Int32) : Int32
end
callback = Proc(Int32, Int32).new { |status| LateExitAliasRuntime.exit(status) }
AliasOrderOutput.putchar(66_i32)
AliasOrderOutput.putchar(10_i32)
callback.call(0_i32)
