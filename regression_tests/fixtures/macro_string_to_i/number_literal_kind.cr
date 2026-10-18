lib LibC
  fun putchar(c : Int32) : Int32
end

{% if "2147483648".to_i == 2147483648_i64 %}
  LibC.putchar(88)
{% else %}
  LibC.putchar(65)
{% end %}
LibC.putchar(10)
