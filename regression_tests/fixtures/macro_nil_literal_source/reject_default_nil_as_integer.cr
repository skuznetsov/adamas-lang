lib LibC
  fun putchar(c : Int32) : Int32
end
def accept_integer(value : Int32) : Int32
  value
end
macro emit(value = nil)
  LibC.putchar(accept_integer({{value}}))
end
emit
