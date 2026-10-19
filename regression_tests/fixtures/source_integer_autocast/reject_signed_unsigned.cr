# Match the original stdlib's source aliases without loading its implementation.
struct Int
  alias Signed = Int8 | Int16 | Int32 | Int64 | Int128
  alias Unsigned = UInt8 | UInt16 | UInt32 | UInt64 | UInt128
  alias Primitive = Signed | Unsigned
end
module Restricted
  struct Int
  end
end
lib LibC
  fun putchar(c : Int32) : Int32
end
def consume(value : Int::Unsigned) : Int32
  65
end
consume(65_i32)
