lib LibC
  fun exit(status : Int32) : NoReturn
end

class Set(T)
  @count : Int32

  def initialize
    SetOrderState.mark(1)
    @count = 0
  end

  def <<(value : T)
    @count += 1
    SetOrderState.mark(2)
    self
  end

  def size : Int32
    @count
  end
end

class SetOrderState
  @@value : Int32 = 0

  def self.mark(value : Int32) : Int32
    @@value = @@value * 10 + value
    value
  end

  def self.value : Int32
    @@value
  end
end

enum RefinedBucket
  Local
  FieldStoreInline
end

def set_complex_value : Int32
  SetOrderState.mark(3)
end

value = 1
members = Set{value, (value = 2), set_complex_value}
LibC.exit(1) unless members.size == 3
LibC.exit(2) unless SetOrderState.value == 31222

absolute_members = ::Set{"absolute"}
LibC.exit(3) unless absolute_members.size == 1

enum_members = ::Set{RefinedBucket::Local, RefinedBucket::FieldStoreInline}
LibC.exit(4) unless enum_members.size == 2

ordinary = [1, 2]
LibC.exit(5) unless ordinary.size == 2
LibC.exit(0)
