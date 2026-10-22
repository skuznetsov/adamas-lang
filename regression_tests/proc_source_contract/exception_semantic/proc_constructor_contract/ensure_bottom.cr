require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
callback = Proc(Int32).new do
begin
  73_i32
ensure
  ProcContractRuntime.exit(0_i32)
end
end
callback.call
