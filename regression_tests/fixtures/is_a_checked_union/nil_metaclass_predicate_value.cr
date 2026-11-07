lib Native
  fun putchar(c : Int32) : Int32
end
struct Span
end
value = nil
Native.putchar(value.is_a?(Span.class | Nil.class) ? 66 : 65)
