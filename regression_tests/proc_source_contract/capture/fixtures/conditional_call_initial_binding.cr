require "proc"

lib CapturePlanRuntime
  fun putchar(value : Int32) : Int32
end

def report_capture(value : Int32)
  CapturePlanRuntime.putchar(65_i32)
end

def report_capture(value : UInt8)
  CapturePlanRuntime.putchar(66_i32)
end

def initial_byte : UInt8
  1_u8
end

outer = if true
  initial_byte()
else
  2_u8
end
callback = Proc(Int32, Int32).new do |replacement|
  outer = replacement
  0_i32
end
callback.call(513_i32)
report_capture(outer)
