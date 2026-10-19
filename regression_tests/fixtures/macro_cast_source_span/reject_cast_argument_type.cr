lib SpanC
  fun putchar(value : Int32) : Int32
end
macro identity(value)
  {{value}}
end
module SpanConsumer
  def self.accept(value : Int32)
    SpanC.putchar(value)
  end
end
class SpanProbe(T)
  def self.emit
    {% if T == Int32 %}
      SpanConsumer.accept(identity("wrong".as(String)))
    {% else %}
      SpanC.putchar(67)
    {% end %}
  end
end
SpanProbe(Int32).emit
