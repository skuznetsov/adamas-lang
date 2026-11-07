class Grandparent
  def initialize(value : Int32 = 65)
  end
end

class Parent < Grandparent
  def initialize(*, file : Int32)
  end
end

class Child < Parent
end

Child.new
