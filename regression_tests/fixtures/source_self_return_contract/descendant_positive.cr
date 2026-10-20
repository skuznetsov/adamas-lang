class InheritedSelfBase
  def self.transport(value) : self
    value
  end
end
class InheritedSelfChild < InheritedSelfBase
end
class InheritedSelfGrandchild < InheritedSelfChild
end
class InheritedSelfOther
end
def observe_child(value : InheritedSelfChild) : Int32
  65
end
value = InheritedSelfChild.transport(InheritedSelfGrandchild.new)
observe_child(value)
