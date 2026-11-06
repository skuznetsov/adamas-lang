lib ProbeC
  fun putchar(value : Int32) : Int32
end

macro exercise
{% outer = "keep" %}
{% result = ["item"].all? do |value, outer|
  value == "item" && outer == "keep"
end %}

{% if result && value == "item" && outer == "keep" %}
  ProbeC.putchar(65)
{% else %}
  ProbeC.putchar(88)
{% end %}
ProbeC.putchar(10)
end
exercise
