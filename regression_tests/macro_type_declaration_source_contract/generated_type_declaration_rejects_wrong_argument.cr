macro emit_typed_acceptor(property)
  {% unless property.is_a?(TypeDeclaration) %}
    {% raise "property is not a TypeDeclaration" %}
  {% end %}

  def self.consume_generated({{property}}) : Int32
    {{property.var.id}}.marker
  end
end

module NegativeScope
  class Marker
    def marker : Int32
      65
    end
  end

  class WrongValue
  end

  emit_typed_acceptor(value : Marker)
end

NegativeScope.consume_generated(NegativeScope::WrongValue.new)
