lib Native
  fun putchar(c : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end
struct Span
end
class Lock
  def write(& : -> F) : F forall F
    begin
      yield
    ensure
      Native.putchar(69)
    end
  end
end
abstract class Reactor
  abstract def connect(socket, addr, timeout)
end
class Parallel < Reactor
  def connect(socket, addr, timeout)
    true
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
    ->{ ->{ Lock.new.write { system_connect(addr, timeout) } }.call }.call
  end
end
class TCPSocket < Socket
end

def hop0 : Int32
  TCPSocket.new.connect(1) {}
end
Native.putchar(hop0)
Native.putchar(10)

fun __crystal_personality(version : Int32, actions : Int32, cls : UInt64, ex : Void*, ctx : Void*) : Int32
  Native._exit(97)
end
fun __crystal_get_exception(ex : Void*) : UInt64
  Native._exit(97)
end
fun __crystal_raise(ex : Void*) : NoReturn
  Native._exit(98)
end
fun __crystal_raise_overflow : NoReturn
  Native._exit(99)
end
