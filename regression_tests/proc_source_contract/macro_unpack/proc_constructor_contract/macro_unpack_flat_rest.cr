require "proc"
lib MacroUnpackFlatRestOutput
  fun putchar(value : Int32) : Int32
end

# Inspect the normalized macro AST without emitting the destructuring body.
# This keeps the oracle focused on pattern transport and avoids an Array
# runtime dependency for the rest binding.
macro inspect_flat_rest_shape(&block)
  {% assignment = block.body.expressions[0] %}
  {% splat = assignment.targets[1] %}
  {% head = assignment.targets[0] %}
  {% tail = splat.exp %}
  {% carrier = assignment.values[0] %}
  {% if assignment.class_name == "MultiAssign" && assignment.targets.size == 2 && assignment.values.size == 1 && head.class_name == "Var" && head.id.stringify == "head" && head.stringify == "head" && splat.class_name == "Splat" && tail.class_name == "Var" && tail.id.stringify == "tail" && tail.stringify == "tail" && splat.exp.id.stringify == "tail" && splat.id.stringify == "*tail" && splat.stringify == "*tail" && carrier.class_name == "Var" %}
    MacroUnpackFlatRestOutput.putchar(65_i32)
  {% else %}
    MacroUnpackFlatRestOutput.putchar(88_i32)
  {% end %}
end

inspect_flat_rest_shape do |(head, *tail)|
  head
end
MacroUnpackFlatRestOutput.putchar(10_i32)
