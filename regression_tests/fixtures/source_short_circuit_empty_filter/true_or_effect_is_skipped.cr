lib C
  fun putchar(value : Int32) : Int32
end

if true || C.putchar(88)
  C.putchar(65)
else
  C.putchar(90)
end
C.putchar(10)
