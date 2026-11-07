lib SpanProbeC
  fun putchar(value : Int32) : Int32
end

struct SpanProbe
  @seconds : Int64
  @nanoseconds : Int64

  def initialize(*, seconds : Int, nanoseconds : Int)
    @seconds = seconds.to_i64
    @nanoseconds = nanoseconds.to_i64
  end

  def matches : Bool
    @seconds == 4_294_967_297_i64 && @nanoseconds == -5_000_000_123_i64
  end
end

span = SpanProbe.new(seconds: 4_294_967_297_i64, nanoseconds: -5_000_000_123_i64)
SpanProbeC.putchar(span.matches ? 65 : 88)
SpanProbeC.putchar(10)
