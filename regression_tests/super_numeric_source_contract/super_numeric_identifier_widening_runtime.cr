class Object
end

lib SuperContractLibC
  fun putchar(value : Int32) : Int32
end

class SuperContractIdentifierParent
  def send_value(value : Int64) : Nil
    SuperContractLibC.putchar(65_i32)
  end
end

class SuperContractIdentifierChild < SuperContractIdentifierParent
  def send_value(value : Int32) : Nil
    super(value)
  end
end

SuperContractIdentifierChild.new.send_value(1_i32)
