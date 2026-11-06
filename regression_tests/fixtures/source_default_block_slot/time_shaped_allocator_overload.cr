@[Link("c")]
lib SlotOwnerC
  fun putchar(value : Int32) : Int32
end
struct SlotStamp
  @value : Int32
  def initialize(@value : Int32)
  end
  def value
    @value
  end
end
class SlotLocation
end
class SlotClock
  @value : Int32
  def self.new(stamp : SlotStamp, location : SlotLocation)
    new(unsafe_seconds: stamp.value)
  end
  def initialize(*, unsafe_seconds : Int32 = 88)
    @value = unsafe_seconds
  end
  def value
    @value
  end
end
SlotOwnerC.putchar(SlotClock.new(SlotStamp.new(65), SlotLocation.new).value)
SlotOwnerC.putchar(SlotClock.new(unsafe_seconds: 66).value)
SlotOwnerC.putchar(10)
