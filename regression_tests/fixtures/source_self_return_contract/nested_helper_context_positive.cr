class NestedContextBase
end
class NestedContextChild < NestedContextBase
end
class NestedContextBase
  def self.make : self
    self.helper
    self.new
  end

  def self.helper : Nil
    nil
  end
end
def observe_nested_context(value : NestedContextChild) : Int32
  65
end
observe_nested_context(NestedContextChild.make)
