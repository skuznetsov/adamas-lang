require "proc"
lib UnpackSecondSlotOutput
  fun putchar(value : Int32) : Int32
end
macro execute_second(&block)
  {{block.args[0]}} = 67_i32
  {{block.args[1]}} = {65_i32, 66_i32}
  {{block.body}}
end
execute_second do |prefix, (first, second)|
  UnpackSecondSlotOutput.putchar(prefix)
  UnpackSecondSlotOutput.putchar(first)
  UnpackSecondSlotOutput.putchar(second)
end
UnpackSecondSlotOutput.putchar(10_i32)
