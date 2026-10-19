lib LibC
  fun putchar(c : Int32) : Int32
  {% if false %}
  {% elsif true %}
    fun bridge_a = putchar(c : Int32) : Int32
    @[Raises]
    fun bridge_b = putchar(c : Int32) : Int32
  {% elsif false %}
    fun bridge_c = putchar(c : Int32) : Int32
  {% else %}
    fun bridge_d = putchar(c : Int32) : Int32
  {% end %}
end
LibC.putchar(65)
LibC.putchar(10)
