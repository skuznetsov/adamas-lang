require "proc"
lib MacroArgsIndexVariableOutput
  fun putchar(value : Int32) : Int32
end
macro inspect_index_variable_argument(&block)
  {% arguments = block.args %}
  {% first_argument = arguments[0] %}
  {% if first_argument.stringify == "plain" %}
    MacroArgsIndexVariableOutput.putchar(67_i32)
  {% else %}
    MacroArgsIndexVariableOutput.putchar(88_i32)
  {% end %}
end
inspect_index_variable_argument do |plain|
  MacroArgsIndexVariableOutput.putchar(68_i32)
end
MacroArgsIndexVariableOutput.putchar(10_i32)
