class Parent
  def initialize(value : Int32)
  end
end

class Child < Parent
  def initialize
  end
end

Child.new(65)
