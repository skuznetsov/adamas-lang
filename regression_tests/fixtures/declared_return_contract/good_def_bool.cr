@[Link("gc")]

def result : Bool
  true
end

if result
  1
end

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
DeclaredReturnOutput.putchar(result ? 65 : 66)
DeclaredReturnOutput.putchar(10)
