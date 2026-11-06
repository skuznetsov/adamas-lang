@[Link("gc")]

class YieldOwner
  def result : Void
    yield
    65
  end
end

YieldOwner.new.result { nil }

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
YieldOwner.new.result { nil }
DeclaredReturnOutput.putchar(65)
DeclaredReturnOutput.putchar(10)
