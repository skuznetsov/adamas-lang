@[Link("c")]
lib RecordOnlyOrderLibC
  fun putchar(value : Int32) : Int32
end

macro emit_parent_then_child
  class Parent
  end

  class Child < Parent
    def value : Int32
      65
    end
  end
end

class RecordOnlyOrderPositive
  {% if true %}
    emit_parent_then_child()
  {% end %}
end

RecordOnlyOrderLibC.putchar(RecordOnlyOrderPositive::Child.new.value)
RecordOnlyOrderLibC.putchar(10)
