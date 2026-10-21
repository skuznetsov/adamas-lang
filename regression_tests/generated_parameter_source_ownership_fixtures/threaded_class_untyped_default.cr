# x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0  x : String = 0 #
lib LibC
  fun putchar(value : Int32) : Int32
end
class GeneratedThreadedParameterSource
  {% if 1 == 1 %}
    {% emitted_value = 65 %}
    def self.value(argument = nil)
      {{ emitted_value }}
    end
  {% end %}
  def self.value(argument : Bool)
    66
  end
end
LibC.putchar(GeneratedThreadedParameterSource.value(nil))
