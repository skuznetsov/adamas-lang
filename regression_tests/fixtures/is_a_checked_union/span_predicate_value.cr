lib Native
  fun putchar(c : Int32) : Int32
end
struct Span
end
value = Span.new
Native.putchar(value.is_a?(Span?) ? 65 : 66)
