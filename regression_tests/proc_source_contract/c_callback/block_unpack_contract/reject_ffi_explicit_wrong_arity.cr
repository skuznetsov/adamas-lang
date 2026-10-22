lib NativeCallback
  fun putchar(Int32) : Int32
  fun exit(Int32) : NoReturn
  fun signal(Int32, (Int32 -> Void)) : (Int32 -> Void)
end

def raise(message)
  NativeCallback.exit(99)
end
def handler(first, second)
  first
end
NativeCallback.signal(30, ->handler(Int32, Int32))
