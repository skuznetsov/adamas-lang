lib C
  fun putchar(value : Int32) : Int32
  fun llabs(value : Int64) : Int64
  fun fabsf(value : Float32) : Float32
  fun fabs(value : Float64) : Float64
end
def value : Float64
  -65.75_f64
end
C.putchar(C.llabs(value))
