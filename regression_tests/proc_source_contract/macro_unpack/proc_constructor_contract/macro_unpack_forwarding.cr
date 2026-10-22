require "proc"
lib UnpackForwardingOutput
  fun putchar(value : Int32) : Int32
end
macro execute_pair(&block)
  {{block.args[0]}} = {65_i32, 66_i32}
  {{block.body}}
end
execute_pair do |(left, right)|
  UnpackForwardingOutput.putchar(left)
  UnpackForwardingOutput.putchar(right)
end
UnpackForwardingOutput.putchar(10_i32)
