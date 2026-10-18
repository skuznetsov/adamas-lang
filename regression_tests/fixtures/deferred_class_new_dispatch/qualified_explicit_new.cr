lib LibC
  fun putchar(value : Int32) : Int32
end

struct QualifiedNewProbe
  def initialize(*, @seconds : Int32, @payload : Int32)
  end

  def payload : Int32
    @payload
  end

  def self.new(*, payload : Int32) : self
    new(seconds: 0, payload: payload)
  end
end

LibC.putchar(QualifiedNewProbe.new(payload: 66).payload)
