class NonIterableStringClassMacroForRejected
  {% for value in "not iterable" %}
    getter {{value.id}}
  {% end %}
end
