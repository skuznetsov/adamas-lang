lib Native
 fun putchar(value : Int32) : Int32
end
def consume(*, file = 65, tail)
 Native.putchar(file)
 Native.putchar(tail)
end
macro forward(**options)
 consume({{ options.double_splat(", ") }}tail: 67)
end
forward(file: 66)
forward
Native.putchar(10)
