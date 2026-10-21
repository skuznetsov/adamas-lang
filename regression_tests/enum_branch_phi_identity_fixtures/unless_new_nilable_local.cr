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

include_value = false
unless include_value
  maybe_value = 67_i32
end
if maybe_value
  GzipEnumOracle.putchar(maybe_value)
else
  GzipEnumOracle.putchar(66_i32)
end
GzipEnumOracle.putchar(10_i32)
