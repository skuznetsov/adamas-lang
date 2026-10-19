lib NumericProbeC
  fun putchar(value : Int32) : Int32
end
def consume(value : UInt16, marker : Int32 = 1) : Int32
  value == 65_u16 && marker == 1 ? 65 : 66
end
NumericProbeC.putchar(consume(65))
NumericProbeC.putchar(10)
