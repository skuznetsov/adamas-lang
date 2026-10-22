source = 7_i32
convert = ->(value : Int8) : Int32 { value.to_i32 }
convert.call(source)
