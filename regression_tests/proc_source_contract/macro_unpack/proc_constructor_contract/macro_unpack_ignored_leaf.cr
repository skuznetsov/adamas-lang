require "proc"
lib UnpackIgnoredOutput
  fun putchar(value : Int32) : Int32
end
macro execute_ignored(&block)
  {{block.args[0]}} = {65_i32, 66_i32}
  {{block.body}}
end
execute_ignored do |(head, _)|
  UnpackIgnoredOutput.putchar(head)
end
UnpackIgnoredOutput.putchar(10_i32)
