lib MacroOutput
  fun putchar(value : Int32) : Int32
end

{% begin %}
  {% array = [0, 1, 2, 3] %}
  {% tuple = {0, 1, 2, 3} %}
  {% range = 1...-1 %}
  {% if array[range] == [1, 2] && tuple[range] == {1, 2} %}
    MacroOutput.putchar(65)
  {% else %}
    MacroOutput.putchar(66)
  {% end %}
  {% if array[..1] == [0, 1] && tuple[-2..] == {2, 3} && array[5..] == nil && tuple[5..] == nil %}
    MacroOutput.putchar(67)
  {% else %}
    MacroOutput.putchar(68)
  {% end %}
{% end %}
