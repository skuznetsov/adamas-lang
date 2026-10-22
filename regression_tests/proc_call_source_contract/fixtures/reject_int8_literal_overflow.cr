convert = ->(value : Int8) : Int32 { value.to_i32 }
convert.call(128_i32)
