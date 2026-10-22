require "proc"
lib ProcResultOutput
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
callback = Proc(Nil).new do
  nested = -> { return }
  nested.call
end
callback.call
ProcResultOutput.putchar(65_i32)
ProcResultOutput.putchar(10_i32)
