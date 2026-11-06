lib LibC
  fun putchar(value : Int32) : Int32
end

macro malformed_statement
  {{ "LibC.putchar())".id }}
end

malformed_statement
LibC.putchar(88)
