lib UnionNumericNative
  fun putchar(value : Int32) : Int32
end

class FirstConversion
  def to_i32 : Int32
    65
  end
end

class SecondConversion
  def to_i32 : Int32
    66
  end
end

def pick(first : Bool) : FirstConversion | SecondConversion
  if first
    FirstConversion.new
  else
    SecondConversion.new
  end
end

def show(value : FirstConversion | SecondConversion)
  UnionNumericNative.putchar(value.to_i32)
end

show(pick(true))
show(pick(false))
UnionNumericNative.putchar(10)
