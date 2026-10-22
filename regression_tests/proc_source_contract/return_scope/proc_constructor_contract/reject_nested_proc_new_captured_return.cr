require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
Proc(Int32).new do
  nested = Proc(Int32).new { return 76_i32 }
  nested.call
end
