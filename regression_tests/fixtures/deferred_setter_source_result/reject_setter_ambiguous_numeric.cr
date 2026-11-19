class Slot
  def size=(value : UInt16)
    value
  end
end

slot = Slot.new
class Slot
  def size=(value : UInt8)
    value
  end
end

slot.size = 0
