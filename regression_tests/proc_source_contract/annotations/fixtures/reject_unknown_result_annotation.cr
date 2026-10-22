require "proc"
value = -> : MissingProcResultType { 65_i32 }
value.call
