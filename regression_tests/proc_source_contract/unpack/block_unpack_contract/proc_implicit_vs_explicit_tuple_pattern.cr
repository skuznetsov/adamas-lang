require "proc"

lib BlockUnpackRuntime
  fun putchar(value : Int32) : Int32
end

implicit = Proc(Tuple(Int32, Int32), Int32).new do |left, right|
  BlockUnpackRuntime.putchar(left)
  BlockUnpackRuntime.putchar(right)
  left
end
explicit = Proc(Tuple(Int32, Int32), Int32).new do |(left, right)|
  BlockUnpackRuntime.putchar(left)
  BlockUnpackRuntime.putchar(right)
  left
end
implicit.call({69_i32, 70_i32})
explicit.call({71_i32, 72_i32})
BlockUnpackRuntime.putchar(10_i32)
