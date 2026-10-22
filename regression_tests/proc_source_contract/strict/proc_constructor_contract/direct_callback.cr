require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

callback = Proc(Int32, Int32).new { |value| value }
ProcContractRuntime.putchar(callback.call(65_i32))
ProcContractRuntime.putchar(10_i32)
