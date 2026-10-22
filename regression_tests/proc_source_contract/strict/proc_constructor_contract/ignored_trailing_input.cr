require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

callback = Proc(Int32, Int32, Int32).new { |first| first }
ProcContractRuntime.putchar(callback.call(67_i32, 90_i32))
ProcContractRuntime.putchar(10_i32)
