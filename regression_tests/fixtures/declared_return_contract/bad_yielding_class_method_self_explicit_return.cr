@[Link("gc")]

class DeclaredReturnYieldingClassSelfFactory
  def self.make : self
    yield
    return DeclaredReturnYieldingClassSelfFactory
  end
end

DeclaredReturnYieldingClassSelfFactory.make { nil }
