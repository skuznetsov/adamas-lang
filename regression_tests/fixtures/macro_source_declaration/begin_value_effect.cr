lib LibC
 fun putchar(value : Int32) : Int32
end
macro emit(node)
LibC.putchar({{node.value}})
end
emit(value : Int32 = begin
  LibC.putchar(65)
  66
end)
LibC.putchar(10)
