lib LibC
  fun putchar(value : Int32) : Int32
end

alias RawPointerElement = Void

def emit_alias(pointer : Pointer(Void))
  LibC.putchar(65)
end

def emit_alias(pointer : Pointer(Pointer(Void)))
  LibC.putchar(66)
end

emit_alias(Pointer(RawPointerElement).new(3_u64))
