lib MacroOutput
  fun putchar(value : Int32) : Int32
end

macro check_range_iteration
  {% limit = 2 %}
  {% range = 1...limit %}
  {% limit = 4 %}
  {% if range.to_a == [1, 2, 3] && range.map { |n| n * 2 } == [2, 4, 6] %}
    MacroOutput.putchar(65)
  {% else %}
    MacroOutput.putchar(66)
  {% end %}
  {% collected = [0, 0, 0] %}
  {% range.each { |n| collected[n - 1] = n } %}
  {% if collected == [1, 2, 3] %}
    MacroOutput.putchar(67)
  {% else %}
    MacroOutput.putchar(68)
  {% end %}
  {% for n in range %}
    MacroOutput.putchar({{ n + 68 }})
  {% end %}
end

check_range_iteration
