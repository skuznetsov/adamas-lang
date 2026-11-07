lib Native
  fun putchar(c : Int32) : Int32
end
struct Span
end
value = Nil
Native.putchar(value.is_a?(Span?) ? 66 : 65)
