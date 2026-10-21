class Object
end

lib SuperContractLibC
  fun putchar(value : Int32) : Int32
end

class SuperContractNumericPairParent
  def send_values(value : Int64, flag : Bool) : Nil
    SuperContractLibC.putchar(67_i32)
  end
end

class SuperContractNumericPairChild < SuperContractNumericPairParent
  def send_values(value : Int32, flag : Bool) : Nil
    super(value, flag)
  end
end

SuperContractNumericPairChild.new.send_values(1_i32, true)
