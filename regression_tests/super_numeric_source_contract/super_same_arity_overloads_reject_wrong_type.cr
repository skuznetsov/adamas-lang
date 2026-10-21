class Object
end

class SuperContractWrongOverloadParent
  def select(value : Bool) : Nil
  end

  def select(value : Int32) : Nil
  end
end

class SuperContractWrongOverloadChild < SuperContractWrongOverloadParent
  def select(value : String) : Nil
    super(value)
  end
end

SuperContractWrongOverloadChild.new.select("wrong")
