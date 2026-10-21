lib GzipEnumOracle
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

def raise(message : String) : NoReturn
  GzipEnumOracle.exit(91_i32)
end

fun __crystal_raise_overflow : NoReturn
  GzipEnumOracle.exit(92_i32)
end

value = 65_i32
skip_value = false
value = 67_i32 unless skip_value
GzipEnumOracle.putchar(value)
GzipEnumOracle.putchar(10_i32)
