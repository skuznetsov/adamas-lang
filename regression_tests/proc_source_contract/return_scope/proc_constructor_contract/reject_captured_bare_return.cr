require "proc"
lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
def owner : Nil
  Proc(Nil).new { return }
  nil
end
owner
