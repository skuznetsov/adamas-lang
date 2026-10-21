lib LibC
  fun putchar(value : Int32) : Int32
end

class ThreadedParameterSource
  {% if 1 == 1 %}
    {% generated_def = "def self.first(argument : Int32); argument; end" %}
    {{ generated_def.id }}
  {% end %}
  {% if 1 == 1 %}
    {% generated_def = "def self.other(argument : UInt8); argument == 1_u8; end" %}
    {{ generated_def.id }}
  {% end %}
end

wrong_argument : Bool = true
LibC.putchar(ThreadedParameterSource.first(wrong_argument))
