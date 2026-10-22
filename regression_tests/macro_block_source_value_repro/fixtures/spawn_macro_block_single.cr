lib LibC
  fun putchar(c : Int32) : Int32
end

macro spawn(*, name = nil, &block)
  {% if block && block.class_name == "Block" && block.body.class_name == "Call" %}
    {{ block.body }}
  {% else %}
    LibC.putchar(88)
  {% end %}
end

spawn name: "single-expression block" do
  LibC.putchar(68)
end
