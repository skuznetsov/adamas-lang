require "proc"
lib MacroUnpackNodeApiOutput
  fun putchar(value : Int32) : Int32
end

macro reject_candidate_only_var_name(&block)
  {% target = block.body.expressions[0].targets[0] %}
  {% if target.name.stringify == "head" %}
    MacroUnpackNodeApiOutput.putchar(65_i32)
  {% end %}
end

reject_candidate_only_var_name do |(head, tail)|
  head
end
MacroUnpackNodeApiOutput.putchar(10_i32)
