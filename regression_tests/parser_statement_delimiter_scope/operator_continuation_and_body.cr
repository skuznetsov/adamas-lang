lib ParserNewlineProbe
  fun putchar(value : Int32) : Int32
end

def invoke(comparator : Proc(Int32, Int32, Int32), left : Int32, right : Int32) : Int32
  comparator.call(left, right)
end

result = invoke(->(left : Int32, right : Int32) {
  if left <
      right
    -1
  elsif left >
      right
    1
  else
    0
  end
}, 1, 2)

ParserNewlineProbe.putchar(48 + result)
ParserNewlineProbe.putchar(10)
