lib SpanC
  fun putchar(value : Int32) : Int32
end
macro identity(value)
  {{value}}
end
class SpanProbe(T)
  def self.emit
    {% if T == Int32 %}
      if value = identity(65.as?(Int32))
        SpanC.putchar(value)
      else
        SpanC.putchar(66)
      end
    {% else %}
      SpanC.putchar(67)
    {% end %}
  end
end
SpanProbe(Int32).emit
