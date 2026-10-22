require "proc"
lib UnpackNestedOutput
  fun putchar(value : Int32) : Int32
end
macro execute_nested(&block)
  {{block.args[0]}} = {65_i32, {66_i32, 67_i32}}
  {{block.body}}
end
execute_nested do |(first, (second, third))|
  UnpackNestedOutput.putchar(first)
  UnpackNestedOutput.putchar(second)
  UnpackNestedOutput.putchar(third)
end
UnpackNestedOutput.putchar(10_i32)
