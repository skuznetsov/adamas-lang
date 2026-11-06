@[Link("gc")]

class DeclaredReturnClassSelfFactory
  def self.make : self
    self
  end
end

DeclaredReturnClassSelfFactory.make
