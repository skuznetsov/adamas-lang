@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

module ErrorFactory
  macro included
    macro from_errno(message, **opts)
      ::\{{ @type }}.from_os_error(\{{ message }}, \{{ opts.double_splat }})
    end
  end
end

class ParentProbe
  include ErrorFactory

  def self.from_os_error(message : String, **opts) : Int32
    C.putchar(80)
    0
  end
end

class ChildProbe < ParentProbe
  def self.from_os_error(message : String, **opts) : Int32
    C.putchar(67)
    0
  end
end

ChildProbe.from_errno("payload")
C.putchar(10)
