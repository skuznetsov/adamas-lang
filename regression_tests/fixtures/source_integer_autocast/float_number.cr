struct Int
  alias Signed = Int8 | Int16 | Int32 | Int64 | Int128
  alias Unsigned = UInt8 | UInt16 | UInt32 | UInt64 | UInt128
  alias Primitive = Signed | Unsigned
end
struct Float
  alias Primitive = Float32 | Float64
end
struct Number
  alias Primitive = Int::Primitive | Float::Primitive
end
lib NumberProbeC
  fun putchar(value : Int32) : Int32
end
def consume(value : Number::Primitive) : Int32
  65
end
NumberProbeC.putchar(consume(1.0_f32))
NumberProbeC.putchar(10)
