def value(flag : Bool) : Bool | UInt8*
  flag ? true : Pointer(UInt8).new(0_u64)
end
lib C
  fun accept(value : UInt8*)
end
C.accept(value(true))
