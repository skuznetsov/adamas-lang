lib ProbeC
  fun putchar(value : Int32) : Int32
end

macro exercise
{% result = [1].all? { |value| value == 1 } %}

{% if result.class_name == "BoolLiteral" && result %}
  ProbeC.putchar(65)
{% else %}
  ProbeC.putchar(88)
{% end %}
ProbeC.putchar(10)
end
exercise
