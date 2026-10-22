require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

callback = Proc(Tuple(Int32, Int32), Int32).new { |first, second| second }
ProcContractRuntime.putchar(callback.call({90_i32, 69_i32}))
ProcContractRuntime.putchar(10_i32)
