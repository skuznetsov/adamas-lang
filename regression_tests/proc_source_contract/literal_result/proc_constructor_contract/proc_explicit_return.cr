require "proc"
lib ProcResultOutput
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
nested = -> { return 68_i32 }
ProcResultOutput.putchar(nested.call)
ProcResultOutput.putchar(10_i32)
