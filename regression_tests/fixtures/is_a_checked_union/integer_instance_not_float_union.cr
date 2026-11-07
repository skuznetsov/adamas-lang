lib Native
 fun putchar(c : Int32) : Int32
end
value = 1
Native.putchar(value.is_a?(Float64 | Nil) ? 66 : 65)
