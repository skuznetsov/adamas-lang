@[Link("c")]
lib SourceBlockSlotOutput
  fun putchar(value : Int32) : Int32
end

class SourceBlockSlotFactory
  def self.new(initial_capacity = 7, &block : -> Int32)
    (yield) &+ initial_capacity
  end
end

value = SourceBlockSlotFactory.new { 65 }
SourceBlockSlotOutput.putchar(value)
SourceBlockSlotOutput.putchar(10)
