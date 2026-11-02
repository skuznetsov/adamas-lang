lib LibC
  fun putchar(c : Int32) : Int32
end
def select_number(first, second, number) : Int32
  number
end
macro emit
  LibC.putchar(select_number(<<-FIRST, <<-SECOND, 65))
    first payload
    FIRST
    second payload
    SECOND
end
emit
LibC.putchar(10)
