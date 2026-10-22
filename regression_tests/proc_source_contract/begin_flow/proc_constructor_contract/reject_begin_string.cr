require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
callback = Proc(Int32).new { begin; "wrong"; end }
callback.call
