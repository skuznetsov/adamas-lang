@[Link("c")]
lib SourceBlockSlotOutput
  fun putchar(value : Int32) : Int32
end

class TwoDefaultBlockMethod
  def self.run(left = 7, right = 20, &block : Int32 -> Int32)
    yield left &+ right &+ 40
  end
end

value = TwoDefaultBlockMethod.run { |sum| sum }
SourceBlockSlotOutput.putchar(value)
SourceBlockSlotOutput.putchar(10)
