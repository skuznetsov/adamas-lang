lib LibC
  fun putchar(c : Int32) : Int32
end
macro emit_default(node)
  LibC.putchar({{node.value}})
end
macro forward(node)
  {{node}}
end
macro forward_named(*, node)
  {{node}}
end
forward(emit_default(@field : Int32 = begin
  LibC.putchar(65)
  66
end))
LibC.putchar(10)
