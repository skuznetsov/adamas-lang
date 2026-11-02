lib LibC
  fun putchar(c : Int32) : Int32
end
def select_number(text, number) : Int32
  number
end
macro emit
  LibC.putchar(select_number(<<-BODY, 65))
    {{ "payload".id }}
    BODY
end
emit
LibC.putchar(10)
