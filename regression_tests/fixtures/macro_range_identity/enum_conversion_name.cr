lib MacroOutput
  fun putchar(value : Int32) : Int32
end

macro check_conversion_name
  {% for name in %w(i16 u64) %}
    {% prefix = name.starts_with?('i') ? "Int".id : (name.starts_with?('u') ? "UInt".id : "Float".id) %}
    {% type = "#{prefix}#{name[1..-1].id}".id %}
    {% if name == "u64" %}
      {% unless type.stringify == "UInt64" %}
        {% raise "expected UInt64, got #{type}" %}
      {% end %}
      MacroOutput.putchar(65)
    {% end %}
  {% end %}
end

check_conversion_name
