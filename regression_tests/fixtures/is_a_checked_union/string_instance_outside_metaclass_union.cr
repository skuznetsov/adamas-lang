class String
end
lib Native
 fun putchar(c : Int32) : Int32
end
value = "x"
Native.putchar(value.is_a?(String.class | Nil.class) ? 66 : 65)
