lib LibC
  fun putchar(c : Int32) : Int32
end

class AllocatorNamedDefaultProbe
  @seconds : Int32
  @nanoseconds : Int32

  def initialize(*, seconds : Int32, nanoseconds : Int32)
    @seconds = seconds
    @nanoseconds = nanoseconds
  end

  # Mirrors Time::Span's narrow keyword constructor wrapper.
  def self.new(*, nanoseconds : Int32)
    new(seconds: 0, nanoseconds: nanoseconds)
  end

  # Mirrors its defaulted keyword wrapper and forwards a complete named shape.
  def self.new(*, seconds : Int32 = 0, nanoseconds : Int32 = 0)
    new(seconds: seconds, nanoseconds: nanoseconds)
  end

  def valid?(seconds : Int32, nanoseconds : Int32) : Bool
    @seconds == seconds && @nanoseconds == nanoseconds
  end
end

narrow = AllocatorNamedDefaultProbe.new(nanoseconds: 7)
defaulted = AllocatorNamedDefaultProbe.new(seconds: 3)
empty = AllocatorNamedDefaultProbe.new
full = AllocatorNamedDefaultProbe.new(seconds: 4, nanoseconds: 6)

LibC.putchar(narrow.valid?(0, 7) ? 49 : 48)
LibC.putchar(defaulted.valid?(3, 0) ? 49 : 48)
LibC.putchar(empty.valid?(0, 0) ? 49 : 48)
LibC.putchar(full.valid?(4, 6) ? 49 : 48)
LibC.putchar(10)
