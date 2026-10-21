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

@[Flags]
enum NestedFlags : UInt8
  None = 0
  Extra = 1
  Name = 2
end

def sink_byte(value : UInt8)
  GzipEnumOracle.putchar(value.to_i32 + 64_i32)
  GzipEnumOracle.putchar(10_i32)
end

sink_byte(NestedFlags::Extra.value)
