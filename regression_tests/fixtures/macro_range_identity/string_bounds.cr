lib MacroOutput
  fun putchar(value : Int32) : Int32
end

{% begin %}
  {% text = "u64" %}
  {% start = 1 %}
  {% range = start..-1 %}
  {% start = 2 %}
  {% if text[range] == "4" && range.begin.stringify == "start" %}
    MacroOutput.putchar(65)
  {% else %}
    MacroOutput.putchar(66)
  {% end %}
  {% if "αβγ"[1...-1] == "β" && "u64"[..1] == "u6" && "u64"[1..] == "64" %}
    MacroOutput.putchar(67)
  {% else %}
    MacroOutput.putchar(68)
  {% end %}
{% end %}

macro check_range_rendering
  {% id = "u64".id %}
  {% symbol = :u64 %}
  {% if id[1..].class_name == "MacroId" && id[1..].stringify == "64" && symbol[1..].class_name == "SymbolLiteral" %}
    MacroOutput.putchar({{ (69..-1).begin }})
  {% else %}
    MacroOutput.putchar(70)
  {% end %}
end

check_range_rendering
