@[Link("gc")]

def result : Void
  yield
  65
end

result { nil }

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
result { nil }
DeclaredReturnOutput.putchar(65)
DeclaredReturnOutput.putchar(10)
