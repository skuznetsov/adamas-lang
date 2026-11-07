lib Native
 fun putchar(c : Int32) : Int32
end
value = Int32
Native.putchar(value.is_a?(Float64.class | Nil.class) ? 66 : 65)
