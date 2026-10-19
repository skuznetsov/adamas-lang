lib NumericProbeC
  fun putchar(value : Int32) : Int32
end
def consume(value : UInt64) : Int32
  value == 65_u64 ? 65 : 66
end
NumericProbeC.putchar(consume(65_u8))
NumericProbeC.putchar(10)
