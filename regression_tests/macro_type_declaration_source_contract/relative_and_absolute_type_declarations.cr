lib C
  fun putchar(value : Int32) : Int32
end

macro assert_typed_declaration(property, expected_type, expected_declaration, expected_value)
  {% unless property.is_a?(TypeDeclaration) %}
    {% raise "property is not a TypeDeclaration" %}
  {% end %}
  {% unless property.type.stringify == expected_type %}
    {% raise "TypeDeclaration#type mismatch: #{property.type.stringify}" %}
  {% end %}
  {% unless property.id.stringify == expected_declaration %}
    {% raise "TypeDeclaration#id mismatch: #{property.id.stringify}" %}
  {% end %}
  {% unless property.stringify == expected_declaration %}
    {% raise "TypeDeclaration stringify mismatch: #{property.stringify}" %}
  {% end %}
  {% unless property.value.stringify == expected_value %}
    {% raise "TypeDeclaration#value mismatch: #{property.value.stringify}" %}
  {% end %}

  def self.by_type_{{property.var.id}}(value : {{property.type}}) : Int32
    value.marker
  end

  def self.by_id_{{property.var.id}}({{property.id}}) : Int32
    {{property.var.id}}.marker
  end

  def self.by_string_{{property.var.id}}({{property}}) : Int32
    {{property.var.id}}.marker
  end
end

module RelativeScope
  class Marker
    def marker : Int32
      65
    end
  end

  assert_typed_declaration(relative_field : Marker = Marker.new,
    "Marker", "relative_field : Marker = Marker.new", "Marker.new")
end

class RootMarker
  def marker : Int32
    66
  end
end

module AbsoluteScope
  assert_typed_declaration(absolute_field : ::RootMarker = ::RootMarker.new,
    "::RootMarker", "absolute_field : ::RootMarker = ::RootMarker.new", "::RootMarker.new")
end

C.putchar(RelativeScope.by_type_relative_field(RelativeScope::Marker.new))
C.putchar(RelativeScope.by_id_relative_field)
C.putchar(RelativeScope.by_string_relative_field)
C.putchar(AbsoluteScope.by_type_absolute_field(::RootMarker.new))
C.putchar(AbsoluteScope.by_id_absolute_field)
C.putchar(AbsoluteScope.by_string_absolute_field)
