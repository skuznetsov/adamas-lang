@[Link("gc")]

class MethodOwner
  def result : Bool
    true
  end
end

if MethodOwner.new.result
  1
end

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
DeclaredReturnOutput.putchar(MethodOwner.new.result ? 65 : 66)
DeclaredReturnOutput.putchar(10)
