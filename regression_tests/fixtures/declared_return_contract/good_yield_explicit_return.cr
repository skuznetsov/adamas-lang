@[Link("gc")]

def result(flag : Bool) : Bool
  if flag
    return true
  end
  yield
  true
end

result(false) { nil }

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
value = result(false) { nil }
DeclaredReturnOutput.putchar(value ? 65 : 66)
DeclaredReturnOutput.putchar(10)
