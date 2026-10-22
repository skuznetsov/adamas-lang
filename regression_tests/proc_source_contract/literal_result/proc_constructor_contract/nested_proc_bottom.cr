require "proc"
lib ProcResultOutput
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
callback = Proc(Int32).new do
  nested = -> { ProcResultOutput.exit(0_i32) }
  nested.call
end
callback.call
ProcResultOutput.putchar(88_i32)
