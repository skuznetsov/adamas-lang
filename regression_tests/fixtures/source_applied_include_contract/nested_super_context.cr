module SharedMarker(T)
  def marker(value : T) : Int32
    super(value)
  end
end

module MarkerTailA
  def marker(value : Int32) : Int32
    65
  end
end

module MarkerTailB
  def marker(value : Int32) : Int32
    66
  end
end

module MarkerWrapperA
  include MarkerTailA
  include SharedMarker(Int32)
end

module MarkerWrapperB
  include MarkerTailB
  include SharedMarker(Int32)
end

class MarkerHostAB
  include MarkerWrapperA
  include MarkerWrapperB
end

class MarkerHostBA
  include MarkerWrapperB
  include MarkerWrapperA
end

lib LibC
  fun putchar(value : Int32) : Int32
end

# Both wrappers include the same SharedMarker(Int32) but have different
# next super providers. Stock Crystal returns BA for these two include orders.
LibC.putchar(MarkerHostAB.new.marker(0))
LibC.putchar(MarkerHostBA.new.marker(0))
LibC.putchar(10)
