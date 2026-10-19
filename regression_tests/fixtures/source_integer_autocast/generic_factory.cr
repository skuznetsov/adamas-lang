lib NumericProbeC
  fun putchar(value : Int32) : Int32
end
struct NumericBox(T)
  def self.new(value : T) : T
    value
  end
end
def consume(value : UInt16) : Int32
  value == 65_u16 ? 65 : 66
end
NumericProbeC.putchar(consume(NumericBox(UInt16).new(65)))
NumericProbeC.putchar(10)
