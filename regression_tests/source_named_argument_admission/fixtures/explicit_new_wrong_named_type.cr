class AllocatorNamedDefaultNegativeProbe
  def initialize(*, nanoseconds : Int32)
  end

  def self.new(*, nanoseconds : Int32)
    new(nanoseconds: nanoseconds)
  end
end

AllocatorNamedDefaultNegativeProbe.new(nanoseconds: "wrong")
