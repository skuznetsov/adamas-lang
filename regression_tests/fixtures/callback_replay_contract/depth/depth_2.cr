lib Native
  fun putchar(c : Int32) : Int32
end
struct Span
end
class Lock
  def write(& : -> F) : F forall F
    yield
  end
end
abstract class Reactor
  abstract def connect(socket, addr, timeout)
end
class Parallel < Reactor
  def connect(socket, addr, timeout)
    65
  end
end
module SystemSocket
  private def system_connect(addr, timeout = nil)
    event_loop.connect(self, addr, timeout)
  end
end
class Socket
  include SystemSocket
  def event_loop : Reactor
    Parallel.new
  end
  def connect(addr, timeout = nil, &)
    timeout = timeout.seconds unless timeout.is_a?(Span?)
    ->{ Lock.new.write { system_connect(addr, timeout) } }.call
  end
end
class TCPSocket < Socket
end

def hop0
  TCPSocket.new.connect(1) { }
end

def hop1
  hop0
end

def hop2
  hop1
end
Native.putchar(hop2)
