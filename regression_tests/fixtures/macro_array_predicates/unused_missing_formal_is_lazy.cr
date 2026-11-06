lib ProbeC
  fun putchar(value : Int32) : Int32
end

macro exercise
{% result = [1].all? do |value, never_read|
  value == 1
end %}

{% if result %}
  ProbeC.putchar(65)
{% else %}
  ProbeC.putchar(88)
{% end %}
ProbeC.putchar(10)
end
exercise
