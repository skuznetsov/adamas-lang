lib LibC
  fun putchar(value : Int32) : Int32
end

macro classify(value)
  {% if value.nil? %}
    LibC.putchar(65)
  {% else %}
    LibC.putchar(66)
  {% end %}
end
