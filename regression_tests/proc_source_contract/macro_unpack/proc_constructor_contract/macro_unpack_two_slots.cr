require "proc"
lib MacroUnpackTwoSlotsOutput
  fun putchar(value : Int32) : Int32
end
macro execute_two_slots(&block)
  {{block.args[0]}} = {65_i32, 66_i32}
  {{block.args[1]}} = {67_i32, 68_i32}
  {{block.body}}
end
execute_two_slots do |(first, second), (third, fourth)|
  MacroUnpackTwoSlotsOutput.putchar(first)
  MacroUnpackTwoSlotsOutput.putchar(second)
  MacroUnpackTwoSlotsOutput.putchar(third)
  MacroUnpackTwoSlotsOutput.putchar(fourth)
end
MacroUnpackTwoSlotsOutput.putchar(10_i32)
