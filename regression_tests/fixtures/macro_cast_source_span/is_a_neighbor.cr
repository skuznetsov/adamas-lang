lib SpanC
  fun putchar(value : Int32) : Int32
end
macro identity(value)
  {{value}}
end
class SpanProbe(T)
  def self.emit
    {% if T == Int32 %}
      if identity(65.is_a?(Int32))
        SpanC.putchar(65)
      else
        SpanC.putchar(66)
      end
    {% else %}
      SpanC.putchar(67)
    {% end %}
  end
end
SpanProbe(Int32).emit
