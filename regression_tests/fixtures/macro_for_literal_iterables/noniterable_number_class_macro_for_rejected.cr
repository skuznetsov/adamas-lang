class NonIterableNumberClassMacroForRejected
  {% for value in 7 %}
    getter {{value.id}}
  {% end %}
end
