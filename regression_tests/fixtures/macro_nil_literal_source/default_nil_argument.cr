lib LibC
  fun putchar(c : Int32) : Int32
end

def accept_nil(value : Nil) : Int32
  65
end
macro emit(value = nil)
  LibC.putchar(accept_nil({{value}}))
end
emit
LibC.putchar(10)
