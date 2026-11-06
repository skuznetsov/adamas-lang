lib LibC
  fun putchar(value : Int32) : Int32
end
{% if true %}
  {% for item in [] of Int32 %}
    class ShouldNotBeGenerated
    end
  {% end %}
{% end %}
LibC.putchar(65)
LibC.putchar(10)
