lib LibC
  fun exit(status : Int32) : NoReturn
end

class NamedCollectionInferenceState
  @@value : Int32 = 0

  def self.mark(value : Int32) : Int32
    @@value = @@value * 10 + value
    value
  end

  def self.value : Int32
    @@value
  end
end

class NamedCollectionInferenceBag(T)
  @count : Int32

  def initialize
    NamedCollectionInferenceState.mark(1)
    @count = 0
  end

  def <<(value : T)
    @count += 1
    NamedCollectionInferenceState.mark(value)
    self
  end

  def count : Int32
    @count
  end
end

enum RefinedBucket
  Small
  Large
end

class NamedCollectionEnumBag(T)
  @count : Int32

  def initialize
    @count = 0
  end

  def <<(value : T)
    @count += 1
    self
  end

  def count : Int32
    @count
  end
end

x = 1
bag = NamedCollectionInferenceBag{x, (x = 2)}
LibC.exit(1) unless bag.count == 2
LibC.exit(2) unless NamedCollectionInferenceState.value == 122

enum_bag = ::NamedCollectionEnumBag{RefinedBucket::Small, RefinedBucket::Large}
LibC.exit(3) unless enum_bag.count == 2

ordinary = [1, 2]
LibC.exit(4) unless ordinary.size == 2
LibC.exit(0)
