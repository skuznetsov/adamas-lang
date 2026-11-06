@[Link("gc")]

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end

class DeclaredReturnYieldingClassSelfFactory
  def marker : Int32
    65
  end

  def self.make : self
    yield
    new
  end
end

value = DeclaredReturnYieldingClassSelfFactory.make { nil }
DeclaredReturnOutput.putchar(value.marker)
DeclaredReturnOutput.putchar(10)
