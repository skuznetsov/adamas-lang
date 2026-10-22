require "proc"
alias EarlyExitResult = NoReturn
lib EarlyExitAliasRuntime
  fun exit(status : Int32) : EarlyExitResult
end
lib AliasOrderOutput
  fun putchar(value : Int32) : Int32
end
callback = Proc(Int32, Int32).new { |status| EarlyExitAliasRuntime.exit(status) }
AliasOrderOutput.putchar(65_i32)
AliasOrderOutput.putchar(10_i32)
callback.call(0_i32)
