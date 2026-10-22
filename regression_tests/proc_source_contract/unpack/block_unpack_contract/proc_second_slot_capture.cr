require "proc"

lib BlockUnpackRuntime
  fun putchar(value : Int32) : Int32
end

outer = 65_i32
callback = Proc(Int32, Tuple(Int32, Int32), Int32).new do |prefix, (outer, tail)|
  BlockUnpackRuntime.putchar(prefix)
  BlockUnpackRuntime.putchar(outer)
  BlockUnpackRuntime.putchar(tail)
  prefix
end
callback.call(66_i32, {67_i32, 68_i32})
BlockUnpackRuntime.putchar(outer)
BlockUnpackRuntime.putchar(10_i32)
