lib Native
  fun putchar(c : Int32) : Int32
end
struct Span
end
value = Span.new
if value.is_a?(Span?)
 Native.putchar(65)
else
 Native.putchar(66)
end
