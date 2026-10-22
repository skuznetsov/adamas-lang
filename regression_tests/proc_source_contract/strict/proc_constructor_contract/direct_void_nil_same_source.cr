require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

void_callback = Proc(Int32, Void).new do |value|
  ProcContractRuntime.putchar(value)
  true
end
nil_callback = Proc(Int32, Nil).new do |value|
  ProcContractRuntime.putchar(value)
  true
end
void_callback.call(86_i32)
nil_callback.call(78_i32)
ProcContractRuntime.putchar(10_i32)
