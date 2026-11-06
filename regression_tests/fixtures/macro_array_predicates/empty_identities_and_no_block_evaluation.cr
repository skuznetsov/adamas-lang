lib ProbeC
  fun putchar(value : Int32) : Int32
end

macro exercise
{% empty = [] of Int32 %}
{% all_empty = empty.all? { |value| value.to_i > 0 } %}
{% any_empty = empty.any? { |value| value.to_i > 0 } %}

{% if all_empty && !any_empty %}
  ProbeC.putchar(65)
{% else %}
  ProbeC.putchar(88)
{% end %}
ProbeC.putchar(10)
end
exercise
