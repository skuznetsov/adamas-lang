require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
callback = Proc(Int32).new do
  ProcContractRuntime.exit(0_i32)
  "unreachable"
end
ProcContractRuntime.putchar(72_i32)
ProcContractRuntime.putchar(10_i32)
callback.call
ProcContractRuntime.exit(91_i32)
