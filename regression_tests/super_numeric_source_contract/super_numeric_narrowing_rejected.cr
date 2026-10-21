class Object
end

class SuperContractNarrowParent
  def require_int32(value : Int32) : Nil
  end
end

class SuperContractNarrowChild < SuperContractNarrowParent
  def require_int32(value : Int64) : Nil
    super(value)
  end
end

SuperContractNarrowChild.new.require_int32(1_i64)
