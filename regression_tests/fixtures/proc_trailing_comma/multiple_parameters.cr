lib Native
  fun putchar(c : Int32) : Int32
end
->(x : Int32, y : Int32,) { Native.putchar(x); Native.putchar(y) }.call(65,66)
