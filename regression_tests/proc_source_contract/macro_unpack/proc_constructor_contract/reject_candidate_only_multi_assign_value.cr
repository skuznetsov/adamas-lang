require "proc"
lib MacroUnpackNodeApiOutput
  fun putchar(value : Int32) : Int32
end

macro reject_candidate_only_multi_assign_value(&block)
  {% assignment = block.body.expressions[0] %}
  {% if assignment.value.class_name == "Var" %}
    MacroUnpackNodeApiOutput.putchar(65_i32)
  {% end %}
end

reject_candidate_only_multi_assign_value do |(head, tail)|
  head
end
MacroUnpackNodeApiOutput.putchar(10_i32)
