lib Native
 fun putchar(value : Int32) : Int32
end
def mark(value)
 Native.putchar(value)
 value
end
def consume(message, *, file, other)
 Native.putchar(file)
 Native.putchar(other)
end
macro forward(message, **options)
 consume({{ message }}, {{ options.double_splat }})
end
forward(mark(65), file: mark(66), other: mark(67))
Native.putchar(10)
