class Object
end

class SuperContractAmbiguousParent
  def choose(value : Int16) : Nil
  end

  def choose(value : UInt16) : Nil
  end
end

class SuperContractAmbiguousChild < SuperContractAmbiguousParent
  def choose(value : UInt8) : Nil
    super(value)
  end
end

SuperContractAmbiguousChild.new.choose(1_u8)
