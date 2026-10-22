require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
callback = Proc(Int32).new do
  begin
    begin
      ProcContractRuntime.exit(0_i32)
    end
  end
end
ProcContractRuntime.putchar(73_i32)
ProcContractRuntime.putchar(10_i32)
callback.call
ProcContractRuntime.exit(91_i32)
