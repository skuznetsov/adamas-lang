class Object
end

lib SuperContractLibC
  fun putchar(value : Int32) : Int32
end

module SuperContractMixin
  def emit(value : Int32) : Nil
    SuperContractLibC.putchar(70_i32)
  end
end

class SuperContractMixinParent
  include SuperContractMixin
end

class SuperContractMixinChild < SuperContractMixinParent
  def emit(value : Int32) : Nil
    super(value)
  end
end

SuperContractMixinChild.new.emit(1_i32)
