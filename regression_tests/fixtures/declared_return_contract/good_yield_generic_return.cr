@[Link("gc")]

def result(value : T) : T forall T
  yield
  value
end

result(1) { nil }

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
value = result(65) { nil }
DeclaredReturnOutput.putchar(value == 65 ? 65 : 66)
DeclaredReturnOutput.putchar(10)
