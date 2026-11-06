@[Link("gc")]

class DeclaredReturnYieldingClassSelfFactory
  def self.make : self
    yield
    self
  end
end

DeclaredReturnYieldingClassSelfFactory.make { nil }
