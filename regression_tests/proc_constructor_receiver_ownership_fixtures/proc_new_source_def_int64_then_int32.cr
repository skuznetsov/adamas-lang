require "proc"

lib ProcConstructorFactOutput
  fun putchar(value : Int32) : Int32
end

long_callback = Proc(Int64, Int64).new { |value| value }
int_callback = Proc(Int32, Int32).new { |value| value }
ProcConstructorFactOutput.putchar(int_callback.call(65_i32))
ProcConstructorFactOutput.putchar(long_callback.call(66_i64).to_i32!)
ProcConstructorFactOutput.putchar(10_i32)
