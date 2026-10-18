lib LibC
  fun putchar(value : Int32) : Int32
end

class PointerVoidStaticIndexProbe(T)
  def self.[](index : Int32) : Pointer(T)
    Pointer(T).new(0_u64)
  end
end

def emit_static_index(pointer : Pointer(Void))
  LibC.putchar(65)
end

def emit_static_index(pointer : Pointer(Pointer(Void)))
  LibC.putchar(66)
end

emit_static_index(PointerVoidStaticIndexProbe(Void)[0])
emit_static_index(PointerVoidStaticIndexProbe(Pointer(Void))[0])
