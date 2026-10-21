class Object
end

class SuperContractLiteralRangeParent
  def accept(value : Int32) : Nil
  end
end

class SuperContractLiteralRangeChild < SuperContractLiteralRangeParent
  def accept(value : Int64) : Nil
    super(2147483648_i64)
  end
end

SuperContractLiteralRangeChild.new.accept(1_i64)
