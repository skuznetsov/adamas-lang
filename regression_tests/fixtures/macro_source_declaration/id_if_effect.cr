lib LibC
 fun putchar(value : Int32) : Int32
end
macro declare(field)
{{field.id}}
end
def condition
 LibC.putchar(65)
 true
end
def marker
 LibC.putchar(66)
 7
end
declare value : Int32 = (if condition
 marker
else
 9
end)
LibC.putchar(10)
