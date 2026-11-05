VALUES = {:global_value}

class ScalarMacroFor
  VALUES = 17

  {% for value in VALUES %}
    def {{ value.id }}
    end
  {% end %}
end
