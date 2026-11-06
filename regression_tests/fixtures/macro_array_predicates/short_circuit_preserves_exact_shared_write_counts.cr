lib ProbeC
  fun putchar(value : Int32) : Int32
end
macro exercise
  {% all_visits = 0 %}
  {% all_result = [true, false, true].all? do |value|
    all_visits = all_visits + 1
    value
  end %}
  {% any_visits = 0 %}
  {% any_result = [true, false, true].any? do |item|
    any_visits = any_visits + 1
    item
  end %}
  {% if !all_result && any_result && all_visits == 2 && any_visits == 1 %}
    ProbeC.putchar(65)
  {% else %}
    ProbeC.putchar(88)
  {% end %}
  ProbeC.putchar(10)
end
exercise
