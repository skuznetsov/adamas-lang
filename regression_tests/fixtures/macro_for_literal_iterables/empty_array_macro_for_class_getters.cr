require "object/properties"

class EmptyArrayMacroForClassGetters
  {% for name in [] of Symbol %}
    getter {{name.id}}
  {% end %}
end

lib EmptyArrayMacroForClassGettersC
  fun putchar(value : Int32) : Int32
end

EmptyArrayMacroForClassGettersC.putchar(69)
EmptyArrayMacroForClassGettersC.putchar(10)
