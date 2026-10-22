require "proc"
lib ProcResultOutput
  fun putchar(value : Int32) : Int32
  fun exit(code : Int32) : NoReturn
end
def enclosing : Int8
  nested = -> { return 65_i64 }
  typed = Proc(Int64).new { nested.call }
  if typed.call == 65_i64
    ProcResultOutput.putchar(65_i32)
  else
    ProcResultOutput.putchar(88_i32)
  end
  1_i8
end
enclosing
ProcResultOutput.putchar(10_i32)
