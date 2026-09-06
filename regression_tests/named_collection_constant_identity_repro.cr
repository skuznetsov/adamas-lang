lib LibC
  fun exit(status : Int32) : NoReturn
end
class ConstantIdentityBag(T)
  # Deliberately differs from Array#size at the same field offset.
  @sentinel : Int32
  def initialize
    @sentinel = 77
  end
  def <<(value : T)
    self
  end
  def size : Int32
    42
  end
end
module Collections
  INFERRED = ConstantIdentityBag{1, 2}
  EXPLICIT = ConstantIdentityBag(Int32){3}
  EMPTY = ConstantIdentityBag(Int32){}
  ORDINARY = [1, 2, 3]
  def self.check : Int32
    return 11 unless INFERRED.size == 42
    return 12 unless EXPLICIT.size == 42
    return 13 unless EMPTY.size == 42
    return 15 unless ORDINARY.size == 3
    0
  end
end
class Holder
  @values = ConstantIdentityBag{1, 2}
  def size : Int32
    @values.size
  end
end
LibC.exit(Collections.check) unless Collections.check == 0
LibC.exit(14) unless Holder.new.size == 42
LibC.exit(0)
