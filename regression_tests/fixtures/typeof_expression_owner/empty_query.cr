lib Native
  fun putchar(c : Int32) : Int32
end
emit = ->(code : typeof(),) { Native.putchar(code) }
