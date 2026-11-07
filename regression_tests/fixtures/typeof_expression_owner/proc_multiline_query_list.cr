lib Native
  fun putchar(c : Int32) : Int32
end
emit = ->(code : typeof(
  65,
  66,
), tail : Int32,) { Native.putchar(code); Native.putchar(tail) }
emit.call(65, 66)
