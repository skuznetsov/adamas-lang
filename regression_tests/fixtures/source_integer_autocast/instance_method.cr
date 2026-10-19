lib NumericProbeC
  fun putchar(value : Int32) : Int32
end
class NumericOwner
  @marker : UInt8
  def initialize
    @marker = 1_u8
  end
  def consume(value : UInt16) : Int32
    value == 65_u16 ? 65 : 66
  end
end
NumericProbeC.putchar(NumericOwner.new.consume(65))
NumericProbeC.putchar(10)
