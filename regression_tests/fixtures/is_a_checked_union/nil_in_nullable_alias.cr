lib Native
  fun putchar(c : Int32) : Int32
end
struct Span
end
alias Timeout = Span?
value = nil
if value.is_a?(Timeout)
 Native.putchar(65)
else
 Native.putchar(66)
end
