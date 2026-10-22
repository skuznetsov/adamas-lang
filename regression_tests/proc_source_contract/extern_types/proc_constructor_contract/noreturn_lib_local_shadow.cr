require "proc"
alias LocalExitResult = Int32
lib LocalExitAliasRuntime
  alias LocalExitResult = NoReturn
  fun exit(status : Int32) : LocalExitResult
end
lib AliasOrderOutput
  fun putchar(value : Int32) : Int32
end
callback = Proc(Int32, Int32).new { |status| LocalExitAliasRuntime.exit(status) }
AliasOrderOutput.putchar(67_i32)
AliasOrderOutput.putchar(10_i32)
callback.call(0_i32)
