require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

callback = Proc(Int32, Nil).new do |code|
  ProcContractRuntime.putchar(code)
  true
end
callback.call(71_i32)
ProcContractRuntime.putchar(10_i32)
