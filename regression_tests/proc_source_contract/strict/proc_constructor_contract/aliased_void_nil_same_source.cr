require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

alias ProcBoundaryVoidCallback = Proc(Int32, Void)
alias ProcBoundaryNilCallback = Proc(Int32, Nil)

void_callback = ProcBoundaryVoidCallback.new do |value|
  ProcContractRuntime.putchar(value)
  true
end
nil_callback = ProcBoundaryNilCallback.new do |value|
  ProcContractRuntime.putchar(value)
  true
end
void_callback.call(65_i32)
nil_callback.call(66_i32)
ProcContractRuntime.putchar(10_i32)
