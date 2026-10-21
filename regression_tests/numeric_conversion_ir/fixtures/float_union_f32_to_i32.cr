def value(flag : Bool) : Float32 | Float64
  flag ? 65.75_f32 : 66.25_f64
end
lib C
  fun putchar(value : Int32) : Int32
end
C.putchar(value(true))
