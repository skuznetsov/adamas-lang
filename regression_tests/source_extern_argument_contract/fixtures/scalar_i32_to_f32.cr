lib C
  fun putchar(value : Int32) : Int32
  fun llabs(value : Int64) : Int64
  fun fabsf(value : Float32) : Float32
  fun fabs(value : Float64) : Float64
end
def value : Int32
  -65_i32
end
C.putchar(C.fabsf(value))
