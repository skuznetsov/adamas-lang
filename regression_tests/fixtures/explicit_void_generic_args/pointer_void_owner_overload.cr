lib LibC
  fun putchar(value : Int32) : Int32
end

def emit_owner(pointer : Pointer(Void))
  LibC.putchar(65)
end

def emit_owner(pointer : Pointer(Pointer(Void)))
  LibC.putchar(66)
end

emit_owner(Pointer(Void).new(1_u64))
emit_owner(Pointer(Pointer(Void)).new(2_u64))
