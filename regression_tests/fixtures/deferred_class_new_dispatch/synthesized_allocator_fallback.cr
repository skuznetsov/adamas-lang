lib LibC
  fun putchar(value : Int32) : Int32
end

struct SynthesizedAllocatorProbe
  MARKER = new(value: 67)

  def initialize(*, @value : Int32)
  end

  def value : Int32
    @value
  end
end

LibC.putchar(SynthesizedAllocatorProbe::MARKER.value)
