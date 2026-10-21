def value(flag : Bool) : Int32 | Int64
  flag ? 65_i32 : 66_i64
end
lib C
  fun putchar(value : Int32) : Int32
end
C.putchar(value(false))
C.putchar(10_i32)
