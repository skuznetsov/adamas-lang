require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

callback = Proc(Tuple(Int32)).new { {true} }
