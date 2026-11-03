@[Link("c")]
lib RecordOnlyEnumLibC
  fun putchar(value : Int32) : Int32
end

macro emit_enum_with_method
  enum Mode
    Ready

    def marker : Int32
      65
    end
  end
end

class RecordOnlyEnumNativeControl
  {% if true %}
    emit_enum_with_method()
  {% end %}
end

RecordOnlyEnumLibC.putchar(RecordOnlyEnumNativeControl::Mode::Ready.marker)
RecordOnlyEnumLibC.putchar(10)
