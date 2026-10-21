class Object
end

lib SuperContractLibC
  fun putchar(value : Int32) : Int32
end

class SuperContractUnsignedBoundaryParent
  def accept(value : UInt32) : Nil
    SuperContractLibC.putchar(65_i32)
  end
end

class SuperContractUnsignedBoundaryChild < SuperContractUnsignedBoundaryParent
  def accept(value : UInt64) : Nil
    super(4294967296_u64)
  end
end

SuperContractUnsignedBoundaryChild.new.accept(1_u64)
