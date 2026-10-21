struct BadPointee
  def to_unsafe : Int32*
    Pointer(Int32).new(0_u64)
  end
end
lib C
  fun free(value : UInt8*)
end
C.free(BadPointee.new)
