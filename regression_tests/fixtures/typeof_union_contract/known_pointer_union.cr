lib Native
  fun getpid : Int32
  fun malloc(size : UInt64) : Void*
  fun free(pointer : Void*) : Void
  fun putchar(value : Int32) : Int32
end
struct Arm
end
pointer = Native.malloc(1_u64)
value = if Native.getpid < 0
  pointer
else
  Arm.new
end
emit = ->(item : typeof(value)) { Native.putchar(item.is_a?(Arm) ? 65 : 66) }
emit.call(pointer)
emit.call(Arm.new)
Native.free(pointer)
