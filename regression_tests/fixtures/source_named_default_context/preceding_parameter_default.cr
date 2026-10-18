@[Link("c")]
lib SourceDefaultPrecedingC
  fun putchar(value : Int32) : Int32
end

class SourceDefaultPrecedingProbe
  def self.emit(seed : Int32, *, value : Int32 = seed, marker : Int32 = 0) : Int32
    SourceDefaultPrecedingC.putchar(value)
  end
end

SourceDefaultPrecedingProbe.emit(65, marker: 1)
SourceDefaultPrecedingC.putchar(10)
