require "proc"
value = -> : String { 65_i64 }
value.call
