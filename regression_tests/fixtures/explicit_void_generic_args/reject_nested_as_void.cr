lib LibC
  fun putchar(value : Int32) : Int32
end

def accept_void_pointer(pointer : Pointer(Void))
  LibC.putchar(65)
end

accept_void_pointer(Pointer(Pointer(Void)).new(1_u64))
