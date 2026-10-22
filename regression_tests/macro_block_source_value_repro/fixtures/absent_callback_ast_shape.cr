lib LibC
  fun putchar(c : Int32) : Int32
end

macro absent_callback_ast_shape(&callback)
  {% if callback.class_name == "Nop" && callback.nil? && !callback %}
    LibC.putchar(79)
  {% else %}
    LibC.putchar(88)
  {% end %}
end
absent_callback_ast_shape
