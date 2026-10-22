require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
def owner : Int32
  Proc(Int32).new { return 7_i32 }
  42_i32
end
owner
