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

outer = 1_u8
callback = Proc(Bool, Int32).new do |take_first|
  if take_first
    outer = 513_i32
  else
    outer = 514_i32
  end
  0_i32
end
callback.call(true)
report_capture(outer)
