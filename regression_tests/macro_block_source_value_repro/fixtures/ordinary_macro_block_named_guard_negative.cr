macro ordinary_callback_guard(&callback)
  {% if callback && callback.class_name == "Block" && callback.body.class_name == "Call" %}
    OrdinaryMacroCallbackBindingMustBePreserved
  {% end %}
end

ordinary_callback_guard do
  guard_call(1)
end
