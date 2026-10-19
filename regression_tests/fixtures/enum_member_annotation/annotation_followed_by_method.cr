annotation EnumMemberMarker
end

lib LibC
  fun putchar(c : Int32) : Int32
end

enum MethodBearing
  First = 65
  @[EnumMemberMarker]
  def marker : Int32
    66
  end
end

LibC.putchar(MethodBearing::First.marker)
LibC.putchar(10)
