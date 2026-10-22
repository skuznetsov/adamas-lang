require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

callback = Proc(Int32, Int32).new { |code| ProcContractRuntime.exit(code) }
ProcContractRuntime.putchar(73_i32)
ProcContractRuntime.putchar(10_i32)
callback.call(0_i32)
ProcContractRuntime.exit(91_i32)
