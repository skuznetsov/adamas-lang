require "proc"

lib BlockUnpackRuntime
  fun putchar(value : Int32) : Int32
end

outer = 1_u8
callback = ->(pair : Tuple(Int32, Int32)) {
  outer, tail = pair
  7_i32
}
callback.call({513_i32, 2_i32})
if outer == 513
  BlockUnpackRuntime.putchar(69_i32)
else
  BlockUnpackRuntime.putchar(70_i32)
end
