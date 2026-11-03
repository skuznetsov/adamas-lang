macro emit_child_then_parent
  class Child < LaterParent
    def value : Int32
      65
    end
  end

  class LaterParent
  end
end

class RecordOnlyOrderNegative
  {% if true %}
    emit_child_then_parent()
  {% end %}
end
