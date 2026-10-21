lib LibC
  fun putchar(value : Int32) : Int32
end
module GeneratedParameterSource
  {% begin %}
    def self.first(argument = nil)
      65_i32
    end
  {% end %}
  {% begin %}
    def self.other(argument : Bool = false)
      66_i32
    end
  {% end %}
end
LibC.putchar(GeneratedParameterSource.other(65_i32))
