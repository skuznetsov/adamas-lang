require "proc"
def enclosing : Int8
  value = -> : Int8 { 65_i64 }
  value.call
  1_i8
end
enclosing
