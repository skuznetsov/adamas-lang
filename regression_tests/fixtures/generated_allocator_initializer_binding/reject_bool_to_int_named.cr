struct SpanProbe
  def initialize(*, seconds : Int, nanoseconds : Int)
  end
end

SpanProbe.new(seconds: true, nanoseconds: 1_i64)
