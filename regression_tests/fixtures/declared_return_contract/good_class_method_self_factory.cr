@[Link("gc")]

lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end

class DeclaredReturnClassSelfFactory
  def marker : Int32
    65
  end

  def self.make : self
    new
  end
end

value = DeclaredReturnClassSelfFactory.make
lib DeclaredReturnOutput
  fun putchar(value : Int32) : Int32
end
DeclaredReturnOutput.putchar(value.marker)
DeclaredReturnOutput.putchar(10)
