struct NullAddress
  def to_unsafe : Void*
    Pointer(Void).new(0_u64)
  end
end
lib C
  fun free(value : Void*)
end
C.free(NullAddress.new)
