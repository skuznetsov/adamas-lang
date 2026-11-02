lib LibC
  fun putchar(c : Int32) : Int32
end
def each_code(text, &)
  yield 65
end
macro emit
  each_code(<<-BODY) do |code|
    payload
    BODY
    LibC.putchar(code)
  end
end
emit
LibC.putchar(10)
