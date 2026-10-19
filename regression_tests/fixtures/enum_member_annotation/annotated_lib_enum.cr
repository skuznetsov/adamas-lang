annotation EnumMemberMarker
end

lib LibC
  fun putchar(c : Int32) : Int32
  enum Options
    @[EnumMemberMarker]
    Removed = 65
    Active = 66
  end
end

LibC.putchar(LibC::Options::Removed.value)
LibC.putchar(LibC::Options::Active.value)
LibC.putchar(10)
