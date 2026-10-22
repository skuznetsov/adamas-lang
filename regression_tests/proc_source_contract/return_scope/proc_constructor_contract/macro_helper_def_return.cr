require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
macro define_helper_with_return
  def helper_return_from_macro : Int32
    return 72_i32
  end
end
define_helper_with_return
callback = Proc(Int32).new { helper_return_from_macro }
ProcContractRuntime.putchar(callback.call)
ProcContractRuntime.putchar(10_i32)
