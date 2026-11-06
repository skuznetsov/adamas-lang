@[Link("gc")]

def result : Nil
  yield
  return 65
end

result { nil }

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
value = result { nil }
DeclaredReturnOutput.putchar(value.nil? ? 65 : 66)
DeclaredReturnOutput.putchar(10)
