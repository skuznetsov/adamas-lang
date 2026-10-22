require "proc"

lib ProcUnpackShadowRuntime
  fun putchar(value : Int32) : Int32
end

outer = 65_i32
tail = 66_i32
bias = 1_i32
ProcUnpackShadowRuntime.putchar(outer)
ProcUnpackShadowRuntime.putchar(tail)

callback = Proc(Tuple(Int32, Int32), Int32).new do |(outer, tail)|
  outer &+ tail &+ bias
end

ProcUnpackShadowRuntime.putchar(outer)
ProcUnpackShadowRuntime.putchar(tail)
result = callback.call({32_i32, 33_i32})
ProcUnpackShadowRuntime.putchar(result)
ProcUnpackShadowRuntime.putchar(outer)
ProcUnpackShadowRuntime.putchar(tail)
ProcUnpackShadowRuntime.putchar(10_i32)
