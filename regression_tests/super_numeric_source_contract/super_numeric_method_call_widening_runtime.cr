class Object
end

lib SuperContractLibC
  fun putchar(value : Int32) : Int32
end

class SuperContractCallExprParent
  def send_value(value : Int64) : Nil
    SuperContractLibC.putchar(66_i32)
  end
end

class SuperContractCallExprChild < SuperContractCallExprParent
  def source_value(value : Int32) : Int32
    value
  end

  def send_value(value : Int32) : Nil
    super(source_value(value))
  end
end

SuperContractCallExprChild.new.send_value(1_i32)
