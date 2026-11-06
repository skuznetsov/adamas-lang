@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

class State
  @@value = 65

  def self.current : Int32
    @@value
  end

  def self.message : String
    @@value = 66
    "payload"
  end
end

module Errno
  def self.value : Int32
    State.current
  end
end

module ErrorFactory
  macro included
    macro from_errno(message, **opts)
      %errno = ::Errno.value
      ::\{{ @type }}.from_os_error(\{{ message }}, %errno, \{{ opts.double_splat }})
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

Probe.from_errno(State.message)
C.putchar(10)
