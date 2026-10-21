lib C
  fun putchar(value : Int32) : Int32
  fun fabsf(value : Float32) : Float32
end
def value : UInt32
  3_000_000_000_u32
end
converted = C.fabsf(value)
if converted > 2_000_000_000.0_f32
  C.putchar(65)
else
  C.putchar(66)
end
