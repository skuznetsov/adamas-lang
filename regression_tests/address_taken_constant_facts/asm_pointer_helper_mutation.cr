lib InlineAsmOracleC
  fun putchar(value : Int32) : Int32
end

def overwrite_int64(pointer : Int64*)
  pointer.value = 66_i64
end

wide = 0_i64
overwrite_int64(pointerof(wide))
InlineAsmOracleC.putchar(wide == 66_i64 ? 66 : 88)
InlineAsmOracleC.putchar(6 &* 7 == 42 ? 67 : 88)
InlineAsmOracleC.putchar(10)
