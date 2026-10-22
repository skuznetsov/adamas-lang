require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
callback = Proc(Int32).new do
begin
  ProcContractRuntime.exit(0_i32)
rescue
  "wrong"
end
end
callback.call
