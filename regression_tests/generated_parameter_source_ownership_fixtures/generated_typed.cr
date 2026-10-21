# x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64#
lib LibC
  fun putchar(value : Int32) : Int32
end

module GeneratedParameterSource
  {% begin %}
    def self.value(argument : Int32)
      argument
    end
  {% end %}
end
value = 66_i32
LibC.putchar(GeneratedParameterSource.value(value))
