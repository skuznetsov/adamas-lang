macro emit_missing_namespace_child
  class Missing::Inner
    def value : Int32
      65
    end
  end
end

class RecordOnlyNamespaceNegative
  {% if true %}
    emit_missing_namespace_child()
  {% end %}
end
