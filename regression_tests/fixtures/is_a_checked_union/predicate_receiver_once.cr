lib Native
  fun putchar(c : Int32) : Int32
end
struct Span
end
def source
 Native.putchar(82)
 nil
end
Native.putchar(source.is_a?(Span?) ? 65 : 66)
