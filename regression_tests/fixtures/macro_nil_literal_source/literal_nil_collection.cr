lib LibC
  fun putchar(c : Int32) : Int32
end

def accept_nil(value : Nil) : Int32
  65
end
macro emit(values)
  LibC.putchar(accept_nil({{values[0]}}))
end
emit([nil])
LibC.putchar(10)
