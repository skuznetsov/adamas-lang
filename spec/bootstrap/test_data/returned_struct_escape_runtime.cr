lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

struct ReturnedValue
  def initialize(@value : Int32)
  end

  def value : Int32
    @value
  end
end

def make_returned_value(value : Int32) : ReturnedValue
  ReturnedValue.new(value)
end

first = make_returned_value(73)
second = make_returned_value(11)
LibC.printf("ADAMAS_RETURNED_STRUCT_ESCAPE_OK:%d,%d\n", first.value, second.value)
