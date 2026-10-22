macro spawn_single_guard(&block)
  {% if block && block.class_name == "Block" && block.body.class_name == "Call" %}
    SpawnMacroBlockSingleBindingMustBePreserved
  {% end %}
end

spawn_single_guard do
  guard_call(1)
end
