lib Native
 fun putchar(value : Int32) : Int32
end
def consume(message, *, file)
 Native.putchar(message)
 file
end
macro forward(message, **opts)
 consume({{ message }}, {{ opts.double_splat }})
end
Native.putchar(forward(65, file: 66))
Native.putchar(10)
