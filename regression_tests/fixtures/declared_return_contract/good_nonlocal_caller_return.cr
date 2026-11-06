@[Link("gc")]

def invoke : Bool
  yield
  true
end

def owner : Int32
  invoke { return 65 }
  66
end

owner

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
DeclaredReturnOutput.putchar(owner)
DeclaredReturnOutput.putchar(10)
