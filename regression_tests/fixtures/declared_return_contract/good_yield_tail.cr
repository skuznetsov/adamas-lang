@[Link("gc")]

def result : Bool
  yield
  true
end

result { nil }

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
value = result { nil }
DeclaredReturnOutput.putchar(value ? 65 : 66)
DeclaredReturnOutput.putchar(10)
