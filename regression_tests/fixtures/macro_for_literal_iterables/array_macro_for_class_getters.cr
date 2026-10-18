require "object/properties"

class ArrayMacroForClassGetters
  {% for name in [:charlie, :delta] %}
    getter {{name.id}} = 3
  {% end %}
end

lib ArrayMacroForClassGettersC
  fun putchar(value : Int32) : Int32
end

value = ArrayMacroForClassGetters.new
ArrayMacroForClassGettersC.putchar(value.charlie | 48)
ArrayMacroForClassGettersC.putchar(value.delta | 48)
ArrayMacroForClassGettersC.putchar(10)
