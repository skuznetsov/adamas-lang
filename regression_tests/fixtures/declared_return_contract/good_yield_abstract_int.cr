@[Link("gc")]
lib ReturnChar
  fun putchar(value : Int32) : Int32
end
def result : Int
  yield
  1_u64
end
def mark(value : UInt64) : Int32
  65
end
ReturnChar.putchar(mark(result {}))
ReturnChar.putchar(10)
