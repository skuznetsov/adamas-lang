lib PrimitiveSiblingOutput
  fun putchar(value : Int32) : Int32
end

class PrimitiveSiblingNative
  @[Primitive(:object_id)]
  def object_id : UInt64
  end

  def object_id(value : Int32) : Int32
    value
  end
end

object = PrimitiveSiblingNative.new
object.object_id
PrimitiveSiblingOutput.putchar(object.object_id(65_i32))
PrimitiveSiblingOutput.putchar(10_i32)
