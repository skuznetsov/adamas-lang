lib LibC
 fun putchar(value : Int32) : Int32
end
macro declare(field)
{{field.id}}
end
def outer(value : Int32)
 value
end
def block_marker
 LibC.putchar(65)
 yield
end
declare value : Int32 = outer(block_marker { LibC.putchar(66); 7 })
LibC.putchar(10)
