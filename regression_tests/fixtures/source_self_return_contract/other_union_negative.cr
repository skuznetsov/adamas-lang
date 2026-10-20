class OtherUnionBase
end
class OtherUnionChild < OtherUnionBase
end
class OtherUnionGrandchild < OtherUnionChild
end
class OtherUnionOther
end
class OtherUnionBase
  def self.choose(flag : Bool) : self
    if flag
      OtherUnionChild.new
    else
      OtherUnionOther.new
    end
  end
end
OtherUnionChild.choose(true)
