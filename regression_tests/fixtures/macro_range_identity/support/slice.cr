macro check_range(range)
  {% if "abcd"[range] == "bc" && range.excludes_end? %}
    MacroOutput.putchar(65)
  {% else %}
    MacroOutput.putchar(66)
  {% end %}
end
