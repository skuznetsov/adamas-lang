require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
lib ProcContractVoidRuntime
  fun _Exit(status : Int32) : Void
end
Proc(Int32).new { ProcContractVoidRuntime._Exit(0_i32) }.call
