lib Native
  fun putchar(c : Int32) : Int32
end
struct Span
end
value = nil
if value.is_a?(Span.class | Nil.class)
 Native.putchar(66)
else
 Native.putchar(65)
end
