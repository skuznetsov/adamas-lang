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

LibC.putchar(ThreadedParameterSource.first(65))
if ThreadedParameterSource.other(1_u8)
  LibC.putchar(66)
end
