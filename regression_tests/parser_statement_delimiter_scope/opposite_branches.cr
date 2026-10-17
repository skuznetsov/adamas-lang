lib ParserNewlineProbe
  fun putchar(value : Int32) : Int32
end

def compare(left : Int32, right : Int32) : Int32
  if left < right
    -1
  elsif left > right
    1
  else
    0
  end
end

ParserNewlineProbe.putchar(48 + compare(1, 2))
ParserNewlineProbe.putchar(48 + compare(2, 1))
ParserNewlineProbe.putchar(48 + compare(2, 2))
ParserNewlineProbe.putchar(10)
