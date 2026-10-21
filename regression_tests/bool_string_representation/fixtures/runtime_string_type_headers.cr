lib OracleC
  fun exit(code : Int32) : NoReturn
  fun putchar(code : Int32) : Int32
  fun memcmp(left : Void*, right : Void*, count : UInt64) : Int32
end

# Compare the runtime type header, not implementation-specific numeric ids.
def same_string_header(left : String, right : String) : Bool
  OracleC.memcmp(left.unsafe_as(Pointer(Void)), right.unsafe_as(Pointer(Void)), 4_u64) == 0
end

def bool_string(value : Bool) : String
  value.to_s
end

number = 7
character = 'x'
left = "a"
right = "b"
OracleC.exit(61) unless same_string_header(number.to_s, "7")
OracleC.exit(62) unless same_string_header(character.to_s, "x")
OracleC.exit(63) unless same_string_header(left + right, "ab")
OracleC.exit(64) unless same_string_header("#{number}", "7")
OracleC.exit(65) unless same_string_header(bool_string(true), "true")
OracleC.exit(66) unless same_string_header(bool_string(false), "false")
OracleC.putchar(72)
