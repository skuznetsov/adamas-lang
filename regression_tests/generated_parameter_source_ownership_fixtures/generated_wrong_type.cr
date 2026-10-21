# x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64 x: UInt64#
lib LibC
  fun putchar(value : Int32) : Int32
end

module GeneratedParameterSource
  {% begin %}
    def self.value(argument : Int32)
      65
    end
  {% end %}
end
input = 65_i64
LibC.putchar(GeneratedParameterSource.value(input))
