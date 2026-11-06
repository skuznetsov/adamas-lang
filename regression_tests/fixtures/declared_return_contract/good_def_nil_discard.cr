@[Link("gc")]

def result : Nil
  65
end

result

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
value = result
DeclaredReturnOutput.putchar(value.nil? ? 65 : 66)
DeclaredReturnOutput.putchar(10)
