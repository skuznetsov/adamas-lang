macro spawn_many_guard(&block)
  {% if block && block.body.class_name == "Expressions" && block.body.expressions.size == 2 && block.body.expressions[1].class_name == "Call" %}
    SpawnMacroBlockExpressionsBindingMustBePreserved
  {% end %}
end

spawn_many_guard do
  guard_call(1)
  guard_call(2)
end
