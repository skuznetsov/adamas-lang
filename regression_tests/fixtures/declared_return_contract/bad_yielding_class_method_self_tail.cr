@[Link("gc")]

class DeclaredReturnYieldingClassSelfFactory
  def self.make : self
    yield
    DeclaredReturnYieldingClassSelfFactory
  end
end

DeclaredReturnYieldingClassSelfFactory.make { nil }
