@[Link("gc")]

class YieldOwner
  def result : Nil
    yield
    65
  end
end

YieldOwner.new.result { nil }

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
value = YieldOwner.new.result { nil }
DeclaredReturnOutput.putchar(value.nil? ? 65 : 66)
DeclaredReturnOutput.putchar(10)
