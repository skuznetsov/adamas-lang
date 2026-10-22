require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
alias NeverReturns = NoReturn
lib ProcContractAliasRuntime
  fun exit(status : Int32) : NeverReturns
end
callback = Proc(Int32).new { ProcContractAliasRuntime.exit(0_i32) }
ProcContractRuntime.putchar(70_i32)
ProcContractRuntime.putchar(10_i32)
callback.call
