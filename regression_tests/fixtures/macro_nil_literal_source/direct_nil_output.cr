lib LibC
  fun putchar(c : Int32) : Int32
end
def accept_nil(value : Nil) : Int32
  65
end
macro emit_literal_nil
  LibC.putchar(accept_nil({{ nil }}))
end
emit_literal_nil
LibC.putchar(10)
