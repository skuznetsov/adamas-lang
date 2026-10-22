require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

callback = Proc(Tuple(Int32, Int32), Int32, Int32).new do |(first, second), third|
  ProcContractRuntime.putchar(first)
  ProcContractRuntime.putchar(second)
  third
end
ProcContractRuntime.putchar(callback.call({74_i32, 75_i32}, 76_i32))
ProcContractRuntime.putchar(10_i32)
