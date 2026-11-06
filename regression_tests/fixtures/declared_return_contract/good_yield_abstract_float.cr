@[Link("gc")]
lib ReturnChar
  fun putchar(value : Int32) : Int32
end
def result : Float
  yield
  1.0_f32
end
def mark(value : Float32) : Int32
  65
end
ReturnChar.putchar(mark(result {}))
ReturnChar.putchar(10)
