lib LibC
  fun putchar(c : Int32) : Int32
end

macro ordinary_block(*, label = nil, &callback)
  {% if callback && callback.class_name == "Block" && callback.body.class_name == "Call" %}
    {{ callback.body }}
  {% else %}
    LibC.putchar(88)
  {% end %}
end

ordinary_block label: "ordinary user macro" do
  LibC.putchar(69)
end
