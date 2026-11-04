lib LibC
  fun exit(status : Int32) : NoReturn
end

class Box(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end

  def self.from(& : Int32 -> T)
    new(yield 2)
  end

  def map(&block : T -> U) : Box(U) forall U
    Box(U).from { yield value }
  end

  def pair_with_key(& : T -> _)
    map { |item| {item, yield item} }
  end
end

paired = Box(Int32).new(2).pair_with_key { |item| item.to_u64! }
LibC.exit(paired.value[0] == 2 && paired.value[1] == 2_u64 ? 0 : 1)
