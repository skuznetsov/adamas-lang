lib NumericProbeC
  fun putchar(value : Int32) : Int32
end
def consume_signed(value : Int64) : Int32
  value == 9223372036854775807_i64 ? 65 : 66
end
def consume_unsigned(value : UInt64) : Int32
  value == 18446744073709551615_u64 ? 65 : 66
end
NumericProbeC.putchar(consume_signed(9223372036854775807_u64))
NumericProbeC.putchar(consume_unsigned(18446744073709551615_u64))
NumericProbeC.putchar(10)
