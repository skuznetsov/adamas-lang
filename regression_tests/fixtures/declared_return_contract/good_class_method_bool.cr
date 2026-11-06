@[Link("gc")]

class MethodOwner
  def self.result : Bool
    true
  end
end

if MethodOwner.result
  1
end

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
DeclaredReturnOutput.putchar(MethodOwner.result ? 65 : 66)
DeclaredReturnOutput.putchar(10)
