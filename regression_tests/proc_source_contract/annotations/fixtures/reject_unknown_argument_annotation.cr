require "proc"
value = ->(value : MissingProcArgumentType) : Int32 { 65_i32 }
value.call(1_i32)
