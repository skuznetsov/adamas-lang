@[Link("gc")]

class MethodOwner
  def result : Nil
    return 65
  end
end

MethodOwner.new.result

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
value = MethodOwner.new.result
DeclaredReturnOutput.putchar(value.nil? ? 65 : 66)
DeclaredReturnOutput.putchar(10)
