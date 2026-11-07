class String
end
lib Native
 fun putchar(c : Int32) : Int32
end
value = String
Native.putchar(value.is_a?(String.class | Nil.class) ? 65 : 66)
