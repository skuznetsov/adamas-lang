@[Link("gc")]

lib Native
  fun putchar(value : Int32) : Int32
end

def result : Void
  yield
  return 65
end

result { nil }
Native.putchar(65)
Native.putchar(10)
