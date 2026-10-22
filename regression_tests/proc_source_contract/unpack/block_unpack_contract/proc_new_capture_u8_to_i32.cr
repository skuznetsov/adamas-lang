require "proc"

lib BlockUnpackRuntime
  fun putchar(value : Int32) : Int32
end

def report_capture(value : Int32)
  BlockUnpackRuntime.putchar(65_i32)
end

def report_capture(value : UInt8)
  BlockUnpackRuntime.putchar(66_i32)
end

outer = 1_u8
callback = Proc(Int32, Tuple(Int32, Int32), Int32).new do |prefix, (outer, tail)|
  7_i32
end
callback.call(3_i32, {513_i32, 2_i32})
report_capture(outer)
