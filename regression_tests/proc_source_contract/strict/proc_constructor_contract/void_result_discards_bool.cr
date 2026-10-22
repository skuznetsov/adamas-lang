require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

callback = Proc(Int32, Void).new do |code|
  ProcContractRuntime.putchar(code)
  true
end
callback.call(72_i32)
ProcContractRuntime.putchar(10_i32)
