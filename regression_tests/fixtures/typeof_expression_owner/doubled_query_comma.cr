lib Native
  fun putchar(c : Int32) : Int32
end
emit = ->(code : typeof(65,,66),) { Native.putchar(code) }
