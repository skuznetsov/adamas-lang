lib LibC
  fun putchar(value : Int32) : Int32
end
fun __crystal_raise_overflow : NoReturn
  while true
  end
end
LibC.putchar(1.is_a?(Int32) ? 65 : 88)
LibC.putchar({1, 2_i64}.is_a?(Tuple(Int32, Int64)) ? 66 : 88)
LibC.putchar(Int32.is_a?(Int32.class) ? 67 : 88)
LibC.putchar(1.is_a?(
  Int32
) ? 68 : 88)
LibC.putchar(1.is_a?(Int32 # guard type
) ? 69 : 88)
LibC.putchar(1.is_a?(Int32 |
 Nil
) ? 70 : 88)
macro emit_check(type)
  LibC.putchar(1.is_a?({{ type }}) ? 71 : 88)
end
emit_check(Int32)
LibC.putchar(10)
