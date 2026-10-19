lib NumericProbeC
  fun putchar(value : Int32) : Int32
end
def consume(value : Int16) : Int32
  value == 255_i16 ? 65 : 66
end
value = 255_u8
NumericProbeC.putchar(consume(value))
NumericProbeC.putchar(10)
