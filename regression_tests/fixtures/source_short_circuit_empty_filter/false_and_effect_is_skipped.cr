lib C
  fun putchar(value : Int32) : Int32
end

if false && C.putchar(88)
  C.putchar(90)
else
  C.putchar(65)
end
C.putchar(10)
