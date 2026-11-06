lib LibC
 fun putchar(value : Int32) : Int32
end
macro declare(field)
{{field.id}}
end
def block_marker(value : Int32)
 LibC.putchar(value)
 yield value
end
declare value : Int32 = (block_marker( 65 ) { |x| LibC.putchar(x &+ 1); 7 })
LibC.putchar(10)
