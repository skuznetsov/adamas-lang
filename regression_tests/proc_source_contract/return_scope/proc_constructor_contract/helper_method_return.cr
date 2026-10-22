require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
@[AlwaysInline]
def legal_helper : Int32
  return 69_i32
end
callback = Proc(Int32).new { legal_helper }
ProcContractRuntime.putchar(callback.call)
ProcContractRuntime.putchar(10_i32)
