class Object
end

lib SuperContractLibC
  fun putchar(value : Int32) : Int32
end

class SuperContractNumericParent
  def send_value(value : Int64) : Nil
    SuperContractLibC.putchar(65_i32)
  end
end

class SuperContractNumericChild < SuperContractNumericParent
  def send_value(value : Int32) : Nil
    super(66)
  end
end

SuperContractNumericChild.new.send_value(1_i32)
