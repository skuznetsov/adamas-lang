lib BlockUnpackRuntime
  fun putchar(value : Int32) : Int32
end

def yield_pair(prefix : Int32, pair : Tuple(Int32, Int32))
  yield prefix, pair
end

outer = 77_i32
result = yield_pair(78_i32, {79_i32, 80_i32}) do |prefix, (outer, tail)|
  BlockUnpackRuntime.putchar(prefix)
  BlockUnpackRuntime.putchar(outer)
  BlockUnpackRuntime.putchar(tail)
  prefix
end
BlockUnpackRuntime.putchar(result)
BlockUnpackRuntime.putchar(outer)
BlockUnpackRuntime.putchar(10_i32)
