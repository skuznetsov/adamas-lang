lib Native
  fun putchar(c : Int32) : Int32
end
->(x : typeof(65),) { Native.putchar(x) }.call(65)
