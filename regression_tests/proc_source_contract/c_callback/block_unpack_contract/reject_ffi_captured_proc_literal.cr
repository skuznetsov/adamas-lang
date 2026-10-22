lib NativeCallback
  fun putchar(Int32) : Int32
  fun exit(Int32) : NoReturn
  fun signal(Int32, (Int32 -> Void)) : (Int32 -> Void)
  fun raise_signal = raise(Int32) : Int32
end

def raise(message)
  NativeCallback.exit(99)
end
captured = 82
NativeCallback.signal(30, ->(value : Int32) { NativeCallback.putchar(captured) })
