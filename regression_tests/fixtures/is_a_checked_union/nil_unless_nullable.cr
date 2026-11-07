lib Native
  fun putchar(c : Int32) : Int32
end
struct Span
end
def connect(timeout = nil)
 timeout = timeout.seconds unless timeout.is_a?(Span?)
 Native.putchar(65) if timeout.nil?
end
connect
