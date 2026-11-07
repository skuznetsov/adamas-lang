lib PrimitiveEmptySiblingOutput
  fun putchar(value : Int32) : Int32
end
class PrimitiveEmptySiblingNative
  @[Primitive(:object_id)]
  def object_id : UInt64
  end
  def object_id(value : Int32) : Nil
  end
end
object = PrimitiveEmptySiblingNative.new
object.object_id(65_i32)
PrimitiveEmptySiblingOutput.putchar(65_i32)
PrimitiveEmptySiblingOutput.putchar(10_i32)
