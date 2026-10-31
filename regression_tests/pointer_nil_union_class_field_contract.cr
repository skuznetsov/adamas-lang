@[Link("c")]
lib PointerNilFieldContractOutput
  fun putchar(value : Int32) : Int32
end

class UnionHolder
  @value : Pointer(Int32) | Nil

  def value=(value : Pointer(Int32) | Nil)
    @value = value
  end

  def value : Pointer(Int32) | Nil
    @value
  end
end

def classify_field(value : Pointer(Int32) | Nil) : Int32
  if value.nil?
    66
  elsif value
    65
  else
    67
  end
end

holder = UnionHolder.new
holder.value = Pointer(Int32).new(16_u64)
PointerNilFieldContractOutput.putchar(classify_field(holder.value))
holder.value = Pointer(Int32).new(0_u64)
PointerNilFieldContractOutput.putchar(classify_field(holder.value))
holder.value = nil
PointerNilFieldContractOutput.putchar(classify_field(holder.value))
