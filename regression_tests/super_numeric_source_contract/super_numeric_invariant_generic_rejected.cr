class Object
end

class SuperContractInvariantBox(T)
end

class SuperContractInvariantParent
  def accept(value : SuperContractInvariantBox(Int64)) : Nil
  end
end

class SuperContractInvariantChild < SuperContractInvariantParent
  def accept(value : SuperContractInvariantBox(Int32)) : Nil
    super(value)
  end
end

SuperContractInvariantChild.new.accept(SuperContractInvariantBox(Int32).new)
