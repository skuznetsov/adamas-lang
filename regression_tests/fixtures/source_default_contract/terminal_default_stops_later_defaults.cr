@[Link("c")]
lib C
 fun putchar(value : Int32) : Int32
 fun exit(status : Int32) : NoReturn
end
def mark(value : Int32) : Int32
 C.putchar(value)
 value
end
def stop : NoReturn
 C.putchar(66)
 C.exit(0)
end
def take(a = mark(65), b = stop, c = mark(67))
 C.putchar(68)
end
take
