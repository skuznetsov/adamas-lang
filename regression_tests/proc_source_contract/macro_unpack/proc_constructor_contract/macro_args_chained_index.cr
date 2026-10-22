require "proc"
lib MacroArgsChainedIndexOutput
  fun putchar(value : Int32) : Int32
end
macro inspect_chained_argument_index(&block)
  {% if block.args[0].stringify == "plain" %}
    MacroArgsChainedIndexOutput.putchar(65_i32)
  {% else %}
    MacroArgsChainedIndexOutput.putchar(88_i32)
  {% end %}
end
inspect_chained_argument_index do |plain|
  MacroArgsChainedIndexOutput.putchar(66_i32)
end
MacroArgsChainedIndexOutput.putchar(10_i32)
