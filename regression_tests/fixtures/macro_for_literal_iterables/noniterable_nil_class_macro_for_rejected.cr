class NonIterableNilClassMacroForRejected
  {% for value in nil %}
    getter {{value.id}}
  {% end %}
end
