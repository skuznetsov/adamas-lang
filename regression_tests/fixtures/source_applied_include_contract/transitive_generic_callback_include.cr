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

module CallbackOuter(U)
  include CallbackLeaf(U)
end

class HostInt32ThenInt64
  include CallbackOuter(Int32)
  include CallbackOuter(Int64)
end

class HostInt64ThenInt32
  include CallbackOuter(Int64)
  include CallbackOuter(Int32)
end

lib LibC
  fun putchar(value : Int32) : Int32
end

# The callback overload makes the inferred block input observable without
# converting the callback argument to a common integer type. Predicted output
# is ABAB followed by a newline; it has not yet been qualified against stock.
LibC.putchar(HostInt32ThenInt64.new.marker(65, current: 0) { |value| CallbackMarker.call(value) })
LibC.putchar(HostInt32ThenInt64.new.marker(66_i64, current: 0) { |value| CallbackMarker.call(value) })
LibC.putchar(HostInt64ThenInt32.new.marker(65, current: 0) { |value| CallbackMarker.call(value) })
LibC.putchar(HostInt64ThenInt32.new.marker(66_i64, current: 0) { |value| CallbackMarker.call(value) })
LibC.putchar(10)
