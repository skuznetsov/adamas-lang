require "proc"
lib MacroUnpackNestedSplatOutput
  fun putchar(value : Int32) : Int32
end

# Inspect the normalized nested pattern only. The original body is not emitted,
# so this checks AST transport without requiring Array/Indexable support.
macro inspect_nested_splat_shape(&block)
  {% expressions = block.body.expressions %}
  {% outer = expressions[0] %}
  {% inner = expressions[1] %}
  {% nested_splat = inner.targets[1] %}
  {% if expressions.size >= 3 && outer.class_name == "MultiAssign" && outer.targets.size == 2 && outer.targets[0].id.stringify == "head" && inner.class_name == "MultiAssign" && inner.targets.size == 2 && inner.targets[0].id.stringify == "middle" && nested_splat.class_name == "Splat" && nested_splat.exp.class_name == "Var" && nested_splat.exp.id.stringify == "tail" %}
    MacroUnpackNestedSplatOutput.putchar(65_i32)
  {% else %}
    MacroUnpackNestedSplatOutput.putchar(88_i32)
  {% end %}
end

inspect_nested_splat_shape do |(head, (middle, *tail))|
  head
end
MacroUnpackNestedSplatOutput.putchar(10_i32)
