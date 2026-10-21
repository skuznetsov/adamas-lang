lib C
  fun putchar(value : Int32) : Int32
  fun htonl(value : UInt32) : UInt32
end
def value : Float32
  3_000_000_000.0_f32
end
converted = C.htonl(value)
if converted == 6_213_810_u32
  C.putchar(65)
else
  C.putchar(66)
end
