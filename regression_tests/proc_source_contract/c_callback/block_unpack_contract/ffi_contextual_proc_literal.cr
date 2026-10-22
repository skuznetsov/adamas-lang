lib NativeCallback
  fun putchar(Int32) : Int32
  fun exit(Int32) : NoReturn
  fun signal(Int32, (Int32 -> Void)) : (Int32 -> Void)
  fun raise_signal = raise(Int32) : Int32
end

def raise(message)
  NativeCallback.exit(99)
end
NativeCallback.signal(30, ->(value) {
  if value == 30
    NativeCallback.putchar(82)
  else
    NativeCallback.putchar(88)
  end
})
NativeCallback.raise_signal(30)
NativeCallback.putchar(68)
NativeCallback.putchar(10)
