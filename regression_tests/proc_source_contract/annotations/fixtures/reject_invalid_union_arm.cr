require "proc"
value = -> : (Int32 | String) { true }
value.call
