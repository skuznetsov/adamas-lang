@[Link("c")]
lib SourceDefaultReceiverC
  fun putchar(value : Int32) : Int32
end

class SourceDefaultReceiverProbe
  def initialize(@bias : Int32)
  end

  def bias : Int32
    @bias
  end

  def emit(*, marker : Int32, value : Int32 = self.bias) : Int32
    SourceDefaultReceiverC.putchar(value)
  end
end

SourceDefaultReceiverProbe.new(67).emit(marker: 1)
SourceDefaultReceiverC.putchar(10)
