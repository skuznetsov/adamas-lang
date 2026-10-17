lib ParserNewlineProbe
  fun putchar(value : Int32) : Int32
end

def invoke(comparator : Proc(Int32, Int32, Int32), left : Int32, right : Int32) : Int32
  comparator.call(left, right)
end

def with_value(value : Int32, &block : Int32 -> Int32) : Int32
  block.call(value)
end

comparator = ->(left : Int32, right : Int32) {
  with_value(left) do |value|
    if value < right
      -1
    elsif value > right
      1
    else
      0
    end
  end
}

result = invoke(comparator, 1, 2)
ParserNewlineProbe.putchar(48 + result)
ParserNewlineProbe.putchar(10)
