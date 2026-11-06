@[Link("gc")]

class DeclaredReturnClassSelfFactory
  def self.make : self
    DeclaredReturnClassSelfFactory
  end
end

DeclaredReturnClassSelfFactory.make
