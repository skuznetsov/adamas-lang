require "proc"
lib MacroUnpackRepeatedIgnoredOutput
  fun putchar(value : Int32) : Int32
end
macro execute_repeated_ignored(&block)
  {{block.args[0]}} = {65_i32, 66_i32, 67_i32}
  {{block.body}}
end
execute_repeated_ignored do |(head, _, _)|
  MacroUnpackRepeatedIgnoredOutput.putchar(head)
end
MacroUnpackRepeatedIgnoredOutput.putchar(10_i32)
