lib Native
 fun putchar(c : Int32) : Int32
end
value = 1
Native.putchar(value.is_a?(Int32.class | Nil.class) ? 66 : 65)
