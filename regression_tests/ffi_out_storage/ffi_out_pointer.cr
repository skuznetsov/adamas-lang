@[Link("c")]
lib OutLocalProbe
  fun strtol(input : UInt8*, end_ptr : UInt8**, base : Int32) : Int64
  fun putchar(value : Int32) : Int32
end

number = OutLocalProbe.strtol("65!".to_unsafe, out tail, 10)
slot = pointerof(tail)
OutLocalProbe.putchar(number.to_i32)
OutLocalProbe.putchar(tail.value.to_i32)
OutLocalProbe.putchar(10)

# The closure and later pointer writes must share the same output storage.
reader = -> { tail.value }
number = OutLocalProbe.strtol("66?".to_unsafe, pointerof(tail), 10)
if pointerof(tail) == slot
  OutLocalProbe.putchar(89)
else
  OutLocalProbe.putchar(78)
end
OutLocalProbe.putchar(number.to_i32)
OutLocalProbe.putchar(reader.call.to_i32)
OutLocalProbe.putchar(10)

# An ordinary assignment after `out` must update the local's payload.
tail = Pointer(UInt8).null
number = OutLocalProbe.strtol("67#".to_unsafe, pointerof(tail), 10)
OutLocalProbe.putchar(number.to_i32)
OutLocalProbe.putchar(tail.value.to_i32)
OutLocalProbe.putchar(10)
