lib NativeCallback
  fun putchar(Int32) : Int32
  fun exit(Int32) : NoReturn
  fun signal(Int32, (Int32 -> Void)) : (Int32 -> Void)
  fun raise_signal = raise(Int32) : Int32
end

def raise(message)
  NativeCallback.exit(99)
end

def handler(value)
  if value == 30
    NativeCallback.putchar(82)
  else
    NativeCallback.putchar(88)
  end
end
def install(callback : Proc(Int32, Int32))
  NativeCallback.signal(30, callback)
end
install(->handler(Int32))
NativeCallback.raise_signal(30)
NativeCallback.putchar(66)
NativeCallback.putchar(10)
