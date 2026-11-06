lib ProbeC
  fun putchar(value : Int32) : Int32
end

macro exercise
{% result = ["stop", "not-an-integer"].all? do |value|
  value != "stop" && value.to_i > 0
end %}

{% if !result %}
  ProbeC.putchar(65)
{% else %}
  ProbeC.putchar(88)
{% end %}
ProbeC.putchar(10)
end
exercise
