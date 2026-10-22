require "proc"
lib MacroUnpackNodeApiOutput
  fun putchar(value : Int32) : Int32
end

macro reject_candidate_only_splat_expr(&block)
  {% splat = block.body.expressions[0].targets[1] %}
  {% if splat.expr.class_name == "Var" %}
    MacroUnpackNodeApiOutput.putchar(65_i32)
  {% end %}
end

reject_candidate_only_splat_expr do |(head, *tail)|
  head
end
MacroUnpackNodeApiOutput.putchar(10_i32)
