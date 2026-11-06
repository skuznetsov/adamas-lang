lib Native
  fun putchar(value : Int32) : Int32
end
macro emit_default(node)
  Native.putchar({{node.value}})
end
emit_default(
  field : Int32
  = 65
)
Native.putchar(10)
