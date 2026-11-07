lib Native
  fun putchar(c : Int32) : Int32
end
emit = ->(code : typeof(65),) { Native.putchar(code) }
emit.call(true)
