require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
callback = Proc(Int32).new do
  nested = -> { return 68_i32 }
  nested.call
end
ProcContractRuntime.putchar(callback.call)
ProcContractRuntime.putchar(10_i32)
