class NonIterableBoolClassMacroForRejected
  {% for value in false %}
    getter {{value.id}}
  {% end %}
end
