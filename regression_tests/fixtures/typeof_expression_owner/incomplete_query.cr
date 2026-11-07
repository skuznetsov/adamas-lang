lib Native
  fun putchar(c : Int32) : Int32
end
emit = ->(code : typeof(1 +),) { Native.putchar(code) }
