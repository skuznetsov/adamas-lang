lib C
  fun putchar(value : Int32) : Int32
end

if NoReturn && NoReturn.bytesize > 0
  C.putchar(66)
else
  C.putchar(65)
end
C.putchar(10)
