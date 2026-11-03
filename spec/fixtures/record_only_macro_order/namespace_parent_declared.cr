@[Link("c")]
lib RecordOnlyNamespaceLibC
  fun putchar(value : Int32) : Int32
end

macro emit_declared_namespace_child
  module Present
  end

  class Present::Inner
    def value : Int32
      65
    end
  end
end

class RecordOnlyNamespacePositive
  {% if true %}
    emit_declared_namespace_child()
  {% end %}
end

RecordOnlyNamespaceLibC.putchar(RecordOnlyNamespacePositive::Present::Inner.new.value)
RecordOnlyNamespaceLibC.putchar(10)
