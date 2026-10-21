class Object
end

lib SuperContractLibC
  fun putchar(value : Int32) : Int32
end

class SuperContractSignedBoundaryParent
  def accept(value : Int32) : Nil
    SuperContractLibC.putchar(65_i32)
  end
end

class SuperContractSignedBoundaryChild < SuperContractSignedBoundaryParent
  def accept(value : Int64) : Nil
    super(-2147483648)
  end
end

SuperContractSignedBoundaryChild.new.accept(1_i64)
