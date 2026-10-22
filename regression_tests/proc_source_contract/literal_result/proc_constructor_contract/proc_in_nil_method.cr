require "proc"
lib ProcResultOutput
  fun putchar(value : Int32) : Int32
  fun exit(code : Int32) : NoReturn
end
def enclosing : Nil
  nested = -> { return 65_i32 }
  ProcResultOutput.putchar(nested.call)
  nil
end
enclosing
ProcResultOutput.putchar(10_i32)
