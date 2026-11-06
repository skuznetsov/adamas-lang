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

class Probe
  def self.from_os_error(message : String, errno : Int32?) : Int32
    C.putchar(errno || 66)
    0
  end
end

Probe.from_os_error(State.message, Errno.value)
C.putchar(10)
