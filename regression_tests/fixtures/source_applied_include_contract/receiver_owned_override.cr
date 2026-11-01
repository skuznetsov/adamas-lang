lib LibC
  fun putchar(value : Int32) : Int32
end

module IncludedValue(T)
  def selected_value : T
    @payload
  end
end

class ReceiverOwnedOverride
  @payload : Int64

  def initialize
    @payload = 64_i64
  end

  include IncludedValue(Int64)

  def selected_value : Int32
    32
  end
end

def emit(value : Int32) : Int32
  if value == 32
    LibC.putchar(65)
  else
    LibC.putchar(88)
  end
end

def emit(value : Int64) : Int32
  if value == 64_i64
    LibC.putchar(66)
  else
    LibC.putchar(88)
  end
end

emit(ReceiverOwnedOverride.new.selected_value)
emit(ReceiverOwnedOverride.new.selected_value())
LibC.putchar(10)
