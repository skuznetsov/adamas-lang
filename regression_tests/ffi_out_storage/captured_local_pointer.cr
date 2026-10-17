@[Link("c")]
lib CapturedLocalOutput
  fun putchar(value : Int32) : Int32
end

value = 65
reader = -> { value }
slot = pointerof(value)
slot.value = 66
CapturedLocalOutput.putchar(reader.call)
value = 67
CapturedLocalOutput.putchar(slot.value)
if pointerof(value) == slot
  CapturedLocalOutput.putchar(89)
else
  CapturedLocalOutput.putchar(78)
end
CapturedLocalOutput.putchar(10)
