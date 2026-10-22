require "proc"
lib ProcResultOutput
  fun putchar(value : Int32) : Int32
  fun exit(code : Int32) : NoReturn
end
def enclosing : Int32
  nested = -> { return true }
  typed = Proc(Bool).new { nested.call }
  if typed.call
    ProcResultOutput.putchar(65_i32)
  else
    ProcResultOutput.putchar(88_i32)
  end
  1_i32
end
enclosing
ProcResultOutput.putchar(10_i32)
