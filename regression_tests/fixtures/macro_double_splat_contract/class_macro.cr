lib Native
 fun putchar(value : Int32) : Int32
end
class Error
 def self.consume(message, *, file)
  Native.putchar(message)
  file
 end
 macro forward(message, **opts)
  {{ @type }}.consume({{ message }}, {{ opts.double_splat }})
 end
end
Native.putchar(Error.forward(65, file: 66))
Native.putchar(10)
