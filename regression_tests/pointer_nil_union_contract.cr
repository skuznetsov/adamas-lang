@[Link("c")]
lib PointerNilOutput
  fun putchar(value : Int32) : Int32
  fun getchar : Int32
end

def next_selector : Int32
  PointerNilOutput.getchar & 15
end

def round_trip_nullable(value : Pointer(Int32) | Nil) : Pointer(Int32) | Int32 | Nil
  value
end

def nullable_source(selector : Int32) : Pointer(Int32) | Nil
  if selector == 0
    Pointer(Int32).new(0_u64)
  elsif selector == 1
    Pointer(Int32).new(16_u64)
  else
    nil
  end
end

def wide_source(selector : Int32) : Pointer(Int32) | Int32 | Nil
  if selector == 0
    Pointer(Int32).new(0_u64)
  elsif selector == 1
    Pointer(Int32).new(16_u64)
  elsif selector == 2
    nil
  else
    41
  end
end

def classify_nullable(value : Pointer(Int32) | Nil) : Int32
  if value.nil?
    66
  elsif value
    65
  else
    67
  end
end

def classify_wide(value : Pointer(Int32) | Int32 | Nil) : Int32
  if value.is_a?(Pointer(Int32))
    value ? 65 : 67
  elsif value.nil?
    66
  else
    68
  end
end

def classify_truth_wide(value : Pointer(Int32) | Int32 | Nil) : Int32
  if value
    value.is_a?(Pointer(Int32)) ? 65 : 68
  else
    value.nil? ? 66 : 67
  end
end

def classify_round_trip(value : Pointer(Int32) | Nil) : Int32
  classify_wide(round_trip_nullable(value))
end

def classify_truth_round_trip(value : Pointer(Int32) | Nil) : Int32
  classify_truth_wide(round_trip_nullable(value))
end

def multi_pointer_source(selector : Int32) : Pointer(Int32) | Pointer(UInt8) | Nil
  if selector == 0
    Pointer(UInt8).new(0_u64)
  elsif selector == 1
    Pointer(Int32).new(0_u64)
  elsif selector == 2
    nil
  elsif selector == 3
    Pointer(UInt8).new(16_u64)
  else
    Pointer(Int32).new(16_u64)
  end
end

def classify_multi_pointer(value : Pointer(Int32) | Pointer(UInt8) | Nil) : Int32
  if value.is_a?(Pointer(Int32))
    65
  elsif value.is_a?(Pointer(UInt8))
    66
  elsif value.nil?
    67
  else
    90
  end
end

def classify_multi_pointer_truth(value : Pointer(Int32) | Pointer(UInt8) | Nil) : Int32
  if value
    value.is_a?(Pointer(Int32)) ? 65 : 66
  elsif value.nil?
    67
  else
    68
  end
end

def pointer_bool_source(selector : Int32) : Pointer(Int32) | Bool | Nil
  if selector == 0
    Pointer(Int32).new(0_u64)
  elsif selector == 1
    false
  elsif selector == 2
    true
  elsif selector == 3
    nil
  else
    Pointer(Int32).new(16_u64)
  end
end

def classify_pointer_bool(value : Pointer(Int32) | Bool | Nil) : Int32
  if !value
    if value.nil?
      66
    elsif value.is_a?(Pointer(Int32))
      67
    else
      69
    end
  else
    value.is_a?(Pointer(Int32)) ? 65 : 68
  end
end

def string_source(selector : Int32) : String | Nil
  selector == 0 ? "payload" : nil
end

def classify_string_nil(value : String | Nil) : Int32
  value.nil? ? 66 : 65
end

def string_truth_source(selector : Int32) : String | Nil
  if selector == 0
    ""
  elsif selector == 1
    "payload"
  else
    nil
  end
end

def classify_string_truth(value : String | Nil) : Int32
  if value
    65
  elsif value.nil?
    66
  else
    67
  end
end
PointerNilOutput.putchar(classify_nullable(nullable_source(next_selector)))
PointerNilOutput.putchar(classify_nullable(nullable_source(next_selector)))
PointerNilOutput.putchar(classify_nullable(nullable_source(next_selector)))
PointerNilOutput.putchar(classify_wide(wide_source(next_selector)))
PointerNilOutput.putchar(classify_wide(wide_source(next_selector)))
PointerNilOutput.putchar(classify_wide(wide_source(next_selector)))
PointerNilOutput.putchar(classify_wide(wide_source(next_selector)))
PointerNilOutput.putchar(classify_round_trip(nullable_source(next_selector)))
PointerNilOutput.putchar(classify_round_trip(nullable_source(next_selector)))
PointerNilOutput.putchar(classify_round_trip(nullable_source(next_selector)))
PointerNilOutput.putchar(classify_truth_round_trip(nullable_source(next_selector)))
PointerNilOutput.putchar(classify_truth_round_trip(nullable_source(next_selector)))
PointerNilOutput.putchar(classify_truth_round_trip(nullable_source(next_selector)))
PointerNilOutput.putchar(classify_multi_pointer(multi_pointer_source(next_selector)))
PointerNilOutput.putchar(classify_multi_pointer(multi_pointer_source(next_selector)))
PointerNilOutput.putchar(classify_multi_pointer(multi_pointer_source(next_selector)))
PointerNilOutput.putchar(classify_multi_pointer(multi_pointer_source(next_selector)))
PointerNilOutput.putchar(classify_multi_pointer(multi_pointer_source(next_selector)))
PointerNilOutput.putchar(classify_pointer_bool(pointer_bool_source(next_selector)))
PointerNilOutput.putchar(classify_pointer_bool(pointer_bool_source(next_selector)))
PointerNilOutput.putchar(classify_pointer_bool(pointer_bool_source(next_selector)))
PointerNilOutput.putchar(classify_pointer_bool(pointer_bool_source(next_selector)))
PointerNilOutput.putchar(classify_pointer_bool(pointer_bool_source(next_selector)))
PointerNilOutput.putchar(classify_string_nil(string_source(next_selector)))
PointerNilOutput.putchar(classify_string_nil(string_source(next_selector)))
PointerNilOutput.putchar(classify_multi_pointer_truth(multi_pointer_source(next_selector)))
PointerNilOutput.putchar(classify_multi_pointer_truth(multi_pointer_source(next_selector)))
PointerNilOutput.putchar(classify_multi_pointer_truth(multi_pointer_source(next_selector)))
PointerNilOutput.putchar(classify_multi_pointer_truth(multi_pointer_source(next_selector)))
PointerNilOutput.putchar(classify_multi_pointer_truth(multi_pointer_source(next_selector)))
PointerNilOutput.putchar(classify_string_truth(string_truth_source(next_selector)))
PointerNilOutput.putchar(classify_string_truth(string_truth_source(next_selector)))
PointerNilOutput.putchar(classify_string_truth(string_truth_source(next_selector)))
