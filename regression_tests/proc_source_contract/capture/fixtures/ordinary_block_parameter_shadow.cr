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

def invoke_with_block(value : Int32, &block : Int32 -> Int32) : Int32
  block.call(value)
end

outer = 1_u8
invoke_with_block(513_i32) do |outer|
  outer = 514_i32
  0_i32
end
report_capture(outer)
