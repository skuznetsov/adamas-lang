require "proc"
lib MacroPlainBlockOutput
  fun putchar(value : Int32) : Int32
end
macro execute_plain(&block)
  {{block.args[0]}} = 67_i32
  {{block.body}}
end
execute_plain do |value|
  MacroPlainBlockOutput.putchar(value)
end
MacroPlainBlockOutput.putchar(10_i32)
