require "proc"

lib BlockUnpackRuntime
  fun putchar(value : Int32) : Int32
end

def report_capture(value : Int32)
  BlockUnpackRuntime.putchar(68_i32)
end

def report_capture(value : String)
  BlockUnpackRuntime.putchar(67_i32)
end

outer = 1_i32
callback = Proc(Tuple(String, String), Int32).new do |(outer, tail)|
  7_i32
end
callback.call({"A", "B"})
report_capture(outer)
