lib SpanC
  fun putchar(value : Int32) : Int32
end
macro identity(value)
  {{value}}
end
class SpanProbe(T)
  def self.emit
    {% if T == Int32 %}
      SpanC.putchar(identity((65).as(Int32)))
    {% else %}
      SpanC.putchar(67)
    {% end %}
  end
end
SpanProbe(Int32).emit
