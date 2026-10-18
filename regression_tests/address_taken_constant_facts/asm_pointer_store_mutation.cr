lib InlineAsmOracleC
  fun putchar(value : Int32) : Int32
end

wide = 0_i64
reference = pointerof(wide)
reference.value = 66_i64
InlineAsmOracleC.putchar(wide == 66_i64 ? 66 : 88)
InlineAsmOracleC.putchar(6 &* 7 == 42 ? 67 : 88)
InlineAsmOracleC.putchar(10)
