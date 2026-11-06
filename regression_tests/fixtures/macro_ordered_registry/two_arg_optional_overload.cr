@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

module ErrorFactory
  macro included
    macro from_errno(message, **opts)
      ::\{{ @type }}.from_os_error(\{{ message }}, 65, \{{ opts.double_splat }})
    end

    macro from_errno(message = nil, errno = nil, **opts)
      ::\{{ @type }}.from_os_error(\{{ message }}, \{{ errno }}, \{{ opts.double_splat }})
    end
  end
end

class Probe
  include ErrorFactory

  def self.from_os_error(message : String, errno : Int32?, **opts) : Int32
    C.putchar(errno || 66)
    0
  end
end

Probe.from_errno("payload", 67)
C.putchar(10)
