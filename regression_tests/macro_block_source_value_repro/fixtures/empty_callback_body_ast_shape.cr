lib LibC
  fun putchar(c : Int32) : Int32
end

macro empty_callback_body_ast_shape(&callback)
  {% if callback && callback.class_name == "Block" && callback.body.class_name == "Nop" && callback.body.nil? && !callback.body %}
    LibC.putchar(80)
  {% else %}
    LibC.putchar(88)
  {% end %}
end
empty_callback_body_ast_shape do
end
