lib LibC
  fun putchar(c : Int32) : Int32
end

macro optional_block(&block)
  {% if block %}
    LibC.putchar(88)
  {% else %}
    LibC.putchar(78)
  {% end %}
end

optional_block
