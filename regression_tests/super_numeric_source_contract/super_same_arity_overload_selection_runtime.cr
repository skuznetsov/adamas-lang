class Object
end

lib SuperContractLibC
  fun putchar(value : Int32) : Int32
end

class SuperContractOverloadParent
  def select(value : Bool) : Nil
    SuperContractLibC.putchar(88_i32)
  end

  def select(value : Int32) : Nil
    SuperContractLibC.putchar(69_i32)
  end
end

class SuperContractIntChild < SuperContractOverloadParent
  def select(value : Int32) : Nil
    super(value)
  end
end

class SuperContractBoolChild < SuperContractOverloadParent
  def select(value : Bool) : Nil
    super(value)
  end
end

SuperContractIntChild.new.select(1_i32)
SuperContractBoolChild.new.select(true)
