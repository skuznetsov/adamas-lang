require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

def require_middle(value : Int32) : Nil
  nil
end

callback = Proc(Int32, Int32, Int32, Int32).new do |first, *middle, last|
  require_middle(middle)
  ProcContractRuntime.putchar(first)
  last
end
ProcContractRuntime.putchar(callback.call(83_i32, 90_i32, 70_i32))
ProcContractRuntime.putchar(10_i32)
