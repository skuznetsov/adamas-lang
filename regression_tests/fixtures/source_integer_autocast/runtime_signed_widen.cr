lib NumericProbeC
  fun putchar(value : Int32) : Int32
end
def consume(value : Int64) : Int32
  value == -1_i64 ? 65 : 66
end
value = -1_i8
NumericProbeC.putchar(consume(value))
NumericProbeC.putchar(10)
