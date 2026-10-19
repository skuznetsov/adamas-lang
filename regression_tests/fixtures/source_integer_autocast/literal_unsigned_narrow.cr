lib NumericProbeC
  fun putchar(value : Int32) : Int32
end
def consume(value : UInt16) : Int32
  value == 65535_u16 ? 65 : 66
end
NumericProbeC.putchar(consume(65535_u32))
NumericProbeC.putchar(10)
