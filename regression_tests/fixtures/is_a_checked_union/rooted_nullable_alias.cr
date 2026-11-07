lib Native
  fun putchar(c : Int32) : Int32
end
struct Span
end
module Clock
 struct Span
 end
 alias Timeout = ::Clock::Span?
end
value = nil
Native.putchar(value.is_a?(::Clock::Timeout) ? 65 : 66)
