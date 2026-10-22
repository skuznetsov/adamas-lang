lib LibC
  fun putchar(c : Int32) : Int32
end

macro rest_argument_named_block_and_callback(*block, &callback)
  {% if block.size == 1 && block[0].class_name == "StringLiteral" && callback && callback.class_name == "Block" && callback.body.class_name == "Call" %}
    {{ callback.body }}
  {% else %}
    LibC.putchar(88)
  {% end %}
end
rest_argument_named_block_and_callback("ordinary rest argument") do
  LibC.putchar(82)
end
