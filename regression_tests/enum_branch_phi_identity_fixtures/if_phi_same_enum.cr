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

enum PhiFlags : UInt8
  Extra = 1
  Name = 2
end

enum OtherFlags : UInt8
  Other = 3
end

def sink_flags(value : PhiFlags)
  GzipEnumOracle.putchar(value.value.to_i32 + 64_i32)
  GzipEnumOracle.putchar(10_i32)
end

selected = PhiFlags::Extra
choose_name = true
selected = PhiFlags::Name if choose_name
sink_flags(selected)
