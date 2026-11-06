lib ProbeC
  fun putchar(value : Int32) : Int32
end

macro exercise
{% result = ["accept", "not-an-integer"].any? do |value|
  value == "accept" || value.to_i > 0
end %}

{% if result %}
  ProbeC.putchar(65)
{% else %}
  ProbeC.putchar(88)
{% end %}
ProbeC.putchar(10)
end
exercise
