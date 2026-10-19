lib NumericProbeC
  fun putchar(value : Int32) : Int32
end
def consume(value : Int8) : Int32
  value == -128_i8 ? 65 : 66
end
NumericProbeC.putchar(consume(-128))
NumericProbeC.putchar(consume(127))
NumericProbeC.putchar(10)
