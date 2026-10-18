@[Link("c")]
lib SourceDefaultGenericReceiverC
  fun putchar(value : Int32) : Int32
end

class SourceDefaultGenericReceiverBase(T)
  def self.source_code : Int32
    65
  end

  def self.emit(*, marker : Int32, value : Int32 = self.source_code) : Int32
    value
  end
end

class SourceDefaultGenericReceiverChild(T) < SourceDefaultGenericReceiverBase(T)
  def self.source_code : Int32
    66
  end
end

alias SourceDefaultGenericReceiverChildI32 = SourceDefaultGenericReceiverChild(Int32)

class SourceDefaultGenericReceiverCaller
  def source_code : Int32
    88
  end

  def run : Int32
    SourceDefaultGenericReceiverC.putchar(SourceDefaultGenericReceiverChild(Int32).emit(marker: 1))
    SourceDefaultGenericReceiverC.putchar(SourceDefaultGenericReceiverChildI32.emit(marker: 2))
    SourceDefaultGenericReceiverC.putchar(10)
  end
end

SourceDefaultGenericReceiverCaller.new.run
