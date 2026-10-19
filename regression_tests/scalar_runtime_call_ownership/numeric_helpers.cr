lib OracleC
  fun exit(code : Int32) : NoReturn
  fun puts(text : UInt8*) : Int32
end

value = -12
OracleC.exit(11) unless value.abs == 12
positive = 9
OracleC.exit(12) unless positive.next_power_of_two == 16
OracleC.exit(13) unless positive.leading_zeros_count == 28
zero = 0
OracleC.exit(14) unless zero.leading_zeros_count == 32
OracleC.exit(15) unless positive.to_f64 == 9.0
fraction = 12.75
OracleC.exit(16) unless fraction.to_i32 == 12
OracleC.exit(17) unless fraction.to_i64 == 12_i64
OracleC.puts("numeric-ok".to_unsafe)
