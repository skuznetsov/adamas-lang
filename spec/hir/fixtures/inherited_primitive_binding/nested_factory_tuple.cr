struct Int
  def floor : self
    self
  end
end

lib PrimitiveBindingOutput
  fun putchar(value : Int32) : Int32
end

class PrimitiveBindingFactory
  def self.make(value : Int64)
    {value.floor, 65_i32}
  end
end

def consume_floor(value : Int64) : Int32
  if value == 1_i64
    67_i32
  else
    88_i32
  end
end

def consume_marker(value : Int32) : Int32
  value
end

floor_value, marker = PrimitiveBindingFactory.make(1_i64)
consume_marker(marker)
PrimitiveBindingOutput.putchar(consume_floor(floor_value))
PrimitiveBindingOutput.putchar(10_i32)
