lib Native
  fun putchar(c : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

module SourceA
  class Lock(T)
    def write(& : -> F) : F forall F
      begin
        yield
      ensure
        Native.putchar(69)
      end
    end
  end

  class Child < Lock(Int32)
  end
end

module SourceB
  class Lock(T)
    def write(& : -> F) : F forall F
      begin
        yield
      ensure
        Native.putchar(70)
      end
    end
  end
end

first = SourceA::Child.new.write { 65 }
Native.putchar(first)
second = SourceB::Lock(Int32).new.write { 66 }
Native.putchar(second)
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
