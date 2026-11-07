lib Native
 fun putchar(value : Int32) : Int32
end
module Factory
 macro included
  macro forward(message, **opts)
   \{{ @type }}.consume(\{{ message }}, \{{ opts.double_splat }})
  end
 end
end
class Error
 include Factory
 def self.consume(message, *, file)
  Native.putchar(message)
  file
 end
end
Native.putchar(Error.forward(65, file: 66))
Native.putchar(10)
