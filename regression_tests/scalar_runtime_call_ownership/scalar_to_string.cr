lib OracleC
  fun exit(code : Int32) : NoReturn
  fun puts(text : UInt8*) : Int32
end

integer = -12
OracleC.exit(21) unless integer.to_s == "-12"
wide = 1234567890123_i64
OracleC.exit(22) unless wide.to_s == "1234567890123"
fraction = 1.5
OracleC.exit(23) unless fraction.to_s == "1.5"
letter = 'z'
OracleC.exit(24) unless letter.to_s == "z"
OracleC.puts("string-ok".to_unsafe)
