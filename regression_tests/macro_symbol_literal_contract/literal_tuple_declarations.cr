module LiteralTupleSymbolMethods
  {% for name, value in {:north => 11, :south => 22} %}
    def self.{{name.id}}
      {{value}}
    end
  {% end %}
end

lib LiteralTupleSymbolC
  {% for name, marker in {:abs => 0} %}
    fun {{name.id}}(value : Int32) : Int32
  {% end %}
end

puts LiteralTupleSymbolMethods.north
puts LiteralTupleSymbolMethods.south
puts LiteralTupleSymbolC.abs(-42)
