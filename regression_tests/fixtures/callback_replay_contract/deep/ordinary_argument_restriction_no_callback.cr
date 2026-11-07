lib Native
  fun putchar(c : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

class Receiver
  def accept(value : Int32) : Int32
    value
  end
end

def wrapper
  -> { Receiver.new.accept(true) }.call
end

Native.putchar(wrapper)
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
