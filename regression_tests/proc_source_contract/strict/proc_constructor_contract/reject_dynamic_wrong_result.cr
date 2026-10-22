require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

callback = Proc(Bool, Int32).new do |condition|
  if condition
    true
  else
    65_i32
  end
end
