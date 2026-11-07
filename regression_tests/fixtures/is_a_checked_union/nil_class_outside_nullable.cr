lib Native
  fun putchar(c : Int32) : Int32
end
struct Span
end
value = Nil
if value.is_a?(Span?)
 Native.putchar(66)
else
 Native.putchar(65)
end
