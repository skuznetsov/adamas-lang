lib LibC
  fun putchar(c : Int32) : Int32
end

macro ordinary_argument_named_block(block, &callback)
  {% if block.class_name == "StringLiteral" && callback && callback.class_name == "Block" && callback.body.class_name == "Call" %}
    {{ callback.body }}
  {% else %}
    LibC.putchar(88)
  {% end %}
end

ordinary_argument_named_block("ordinary argument named block") do
  LibC.putchar(72)
end
