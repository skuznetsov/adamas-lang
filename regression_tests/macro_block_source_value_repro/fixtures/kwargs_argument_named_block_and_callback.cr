lib LibC
  fun putchar(c : Int32) : Int32
end

macro kwargs_argument_named_block_and_callback(**block, &callback)
  {% if block.size == 1 && block[:label].class_name == "StringLiteral" && callback && callback.class_name == "Block" && callback.body.class_name == "Call" %}
    {{ callback.body }}
  {% else %}
    LibC.putchar(88)
  {% end %}
end
kwargs_argument_named_block_and_callback(label: "ordinary named argument") do
  LibC.putchar(83)
end
