class Object
end

class SuperContractLaterMismatchParent
  def send_values(value : Int64, flag : Bool) : Nil
  end
end

class SuperContractLaterMismatchChild < SuperContractLaterMismatchParent
  def send_values(value : Int32, flag : String) : Nil
    super(value, flag)
  end
end

SuperContractLaterMismatchChild.new.send_values(1_i32, "wrong")
