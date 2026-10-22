require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
callback = Proc(Bool, Int32).new do |flag|
  begin
    if flag
      ProcContractRuntime.exit(0_i32)
    else
      74_i32
    end
  end
end
ProcContractRuntime.putchar(74_i32)
ProcContractRuntime.putchar(10_i32)
callback.call(false)
