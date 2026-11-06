@[Link("gc")]

class DeclaredReturnClassSelfFactory
  def self.make : self
    return DeclaredReturnClassSelfFactory
  end
end

DeclaredReturnClassSelfFactory.make
