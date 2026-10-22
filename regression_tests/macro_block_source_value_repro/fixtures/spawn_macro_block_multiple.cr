lib LibC
  fun putchar(c : Int32) : Int32
end

macro spawn_many(&block)
  {% if block && block.class_name == "Block" && block.body.class_name == "Expressions" && block.body.expressions.size == 2 && block.body.expressions[0].class_name == "Call" %}
    {{ block.body }}
  {% else %}
    LibC.putchar(88)
  {% end %}
end

spawn_many do
  LibC.putchar(70)
  LibC.putchar(71)
end
