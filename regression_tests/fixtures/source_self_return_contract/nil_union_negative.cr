class NilUnionBase
end
class NilUnionChild < NilUnionBase
end
class NilUnionGrandchild < NilUnionChild
end
class NilUnionBase
  def self.choose(flag : Bool) : self
    if flag
      NilUnionChild.new
    else
      nil
    end
  end
end
NilUnionChild.choose(true)
