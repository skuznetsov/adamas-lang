struct StaticArray(T, N)
  def pair_with_key(& : T -> _)
    map { |item| {item, yield item} }
  end
end

class Left
end

class Right
end

items = StaticArray(Left | Right, 2).new { |index| index == 0 ? Left.new : Right.new }
paired = items.pair_with_key { |item| item.is_a?(Left) ? 2_u64 : 1_u64 }
exit 1 unless paired[0][0].is_a?(Left) && paired[0][1] == 2_u64
exit 2 unless paired[1][0].is_a?(Right) && paired[1][1] == 1_u64
