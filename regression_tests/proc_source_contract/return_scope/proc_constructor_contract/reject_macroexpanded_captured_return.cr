require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
macro captured_return_from_macro
  return 75_i32
end
Proc(Int32).new { captured_return_from_macro }
