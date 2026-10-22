require "proc"
lib ProcResultOutput
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
nested = ->(flag : Bool) do
  if flag
    return 65_i32
  end
  66_i32
end
ProcResultOutput.putchar(nested.call(true))
ProcResultOutput.putchar(nested.call(false))
ProcResultOutput.putchar(10_i32)
