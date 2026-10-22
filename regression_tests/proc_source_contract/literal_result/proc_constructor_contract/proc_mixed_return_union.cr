require "proc"
lib ProcResultOutput
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
nested = ->(flag : Bool) do
  if flag
    return 65_i32
  end
  "B"
end
value = nested.call(true)
if value.is_a?(Int32)
  ProcResultOutput.putchar(value)
else
  ProcResultOutput.putchar(88_i32)
end
other = nested.call(false)
if other.is_a?(String)
  ProcResultOutput.putchar(66_i32)
else
  ProcResultOutput.putchar(88_i32)
end
ProcResultOutput.putchar(10_i32)
