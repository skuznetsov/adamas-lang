require "proc"
value = -> : String { return 65_i64 }
value.call
