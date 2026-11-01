module CallbackMarker
  def self.call(value : Int32) : Int32
    65
  end

  def self.call(value : Int64) : Int32
    66
  end
end

module CallbackLeaf(T)
  def marker(value : T, current ignored : Int32, & : T -> Int32) : Int32
    yield value
  end
end

module CallbackOuterInt32ThenInt64
  include CallbackLeaf(Int32)
  include CallbackLeaf(Int64)
end

module CallbackOuterInt64ThenInt32
  include CallbackLeaf(Int64)
  include CallbackLeaf(Int32)
end

class NestedHostInt32ThenInt64
  include CallbackOuterInt32ThenInt64
end

class NestedHostInt64ThenInt32
  include CallbackOuterInt64ThenInt32
end

lib LibC
  fun putchar(value : Int32) : Int32
end

# This pressures the nested MRO case: each selected outer application contains
# two valid applications of the same generic leaf. Predicted output is ABAB
# followed by a newline; it has not yet been qualified against stock.
LibC.putchar(NestedHostInt32ThenInt64.new.marker(65, current: 0) { |value| CallbackMarker.call(value) })
LibC.putchar(NestedHostInt32ThenInt64.new.marker(66_i64, current: 0) { |value| CallbackMarker.call(value) })
LibC.putchar(NestedHostInt64ThenInt32.new.marker(65, current: 0) { |value| CallbackMarker.call(value) })
LibC.putchar(NestedHostInt64ThenInt32.new.marker(66_i64, current: 0) { |value| CallbackMarker.call(value) })
LibC.putchar(10)
