def value(flag : Bool) : Int32 | String
  flag ? 65_i32 : "B"
end
lib C
  fun putchar(value : Int32) : Int32
end
C.putchar(value(true))
