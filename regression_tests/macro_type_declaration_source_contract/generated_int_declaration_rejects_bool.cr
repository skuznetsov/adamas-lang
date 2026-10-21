macro emit_int_acceptor(property)
  {% unless property.is_a?(TypeDeclaration) %}
    {% raise "property is not a TypeDeclaration" %}
  {% end %}
  {% unless property.type.stringify == "Int32" %}
    {% raise "Int32 TypeDeclaration type mismatch: #{property.type.stringify}" %}
  {% end %}

  def self.consume_int(value : {{property.type}}) : Int32
    65
  end
end

module PrimitiveScope
  emit_int_acceptor(item : Int32 = 65)
end

PrimitiveScope.consume_int(true)
