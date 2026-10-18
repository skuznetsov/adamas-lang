lib LibC
  fun putchar(c : Int32) : Int32
end

{% if "9223372036854775807".to_i.stringify == "9223372036854775807" %}
  LibC.putchar(65)
{% else %}
  LibC.putchar(88)
{% end %}
LibC.putchar(10)
