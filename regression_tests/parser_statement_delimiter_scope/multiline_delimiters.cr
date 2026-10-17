lib ParserNewlineProbe
  fun putchar(value : Int32) : Int32
end

def combine(left : Int32, right : Int32) : Int32
  left + right
end

def sum3(first : Int32, second : Int32, third : Int32) : Int32
  first + second + third
end

values = [3,
  4]
result = sum3(
  1 +
    2,
  combine(
    3,
    4
  ),
  values[
    0
  ]
)
ParserNewlineProbe.putchar(48 + result)
ParserNewlineProbe.putchar(10)
