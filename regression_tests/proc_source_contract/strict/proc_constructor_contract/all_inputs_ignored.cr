require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

callback = Proc(Int32, Int32).new { 68_i32 }
ProcContractRuntime.putchar(callback.call(90_i32))
ProcContractRuntime.putchar(10_i32)
