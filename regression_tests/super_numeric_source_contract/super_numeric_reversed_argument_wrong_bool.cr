class Object
end

class SuperContractReverseParent
  def send_values(flag : Bool, value : Int64) : Nil
  end
end

class SuperContractReverseChild < SuperContractReverseParent
  def send_values(flag : String, value : Int32) : Nil
    super(flag, value)
  end
end

SuperContractReverseChild.new.send_values("wrong", 1_i32)
