@[Link("gc")]

class MethodOwner
  def result : Void
    return 65
  end
end

MethodOwner.new.result

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
MethodOwner.new.result
DeclaredReturnOutput.putchar(65)
DeclaredReturnOutput.putchar(10)
