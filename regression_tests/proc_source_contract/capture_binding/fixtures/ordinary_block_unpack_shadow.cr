lib ProcUnpackShadowRuntime
  fun putchar(value : Int32) : Int32
end

def yield_pair(pair : Tuple(Int32, Int32))
  yield pair
end

outer = 65_i32
tail = 66_i32
bias = 1_i32
ProcUnpackShadowRuntime.putchar(outer)
ProcUnpackShadowRuntime.putchar(tail)

result = yield_pair({32_i32, 33_i32}) do |(outer, tail)|
  outer &+ tail &+ bias
end

ProcUnpackShadowRuntime.putchar(result)
ProcUnpackShadowRuntime.putchar(outer)
ProcUnpackShadowRuntime.putchar(tail)
ProcUnpackShadowRuntime.putchar(10_i32)
