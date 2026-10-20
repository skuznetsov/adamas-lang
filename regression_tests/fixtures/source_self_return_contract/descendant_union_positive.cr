class DescendantUnionBase
end
class DescendantUnionChild < DescendantUnionBase
end
class DescendantUnionGrandchild < DescendantUnionChild
end
class DescendantUnionOther
end
class DescendantUnionBase
  def self.choose(flag : Bool) : self
    if flag
      DescendantUnionChild.new
    else
      DescendantUnionGrandchild.new
    end
  end
end
def observe_descendant_union(value : DescendantUnionChild) : Int32
  65
end
observe_descendant_union(DescendantUnionChild.choose(true))
