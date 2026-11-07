lib Native
  fun putchar(c : Int32) : Int32
end
struct Span
end
value = Nil
if value.is_a?(Span.class | Nil.class)
 Native.putchar(65)
else
 Native.putchar(66)
end
