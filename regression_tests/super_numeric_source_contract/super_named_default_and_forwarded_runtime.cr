class Object
end

lib SuperContractLibC
  fun putchar(value : Int32) : Int32
end

class SuperContractCallParent
  def named(value : Int32) : Nil
    SuperContractLibC.putchar(66_i32)
  end

  def defaulted(value : Int32, marker : Int32 = 67_i32) : Nil
    SuperContractLibC.putchar(marker)
  end

  def forwarded(value : Int32) : Nil
    SuperContractLibC.putchar(68_i32)
  end
end

class SuperContractCallChild < SuperContractCallParent
  def named(value : Int32) : Nil
    super(value: value)
  end

  def defaulted(value : Int32) : Nil
    super(value)
  end

  def forwarded(value : Int32) : Nil
    super
  end
end

child = SuperContractCallChild.new
child.named(1_i32)
child.defaulted(1_i32)
child.forwarded(1_i32)
