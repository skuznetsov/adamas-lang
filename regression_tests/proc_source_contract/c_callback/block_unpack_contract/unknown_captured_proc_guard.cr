lib NativeCallback
  fun putchar(Int32) : Int32
  fun exit(Int32) : NoReturn
  fun signal(Int32, (Int32 -> Void)) : (Int32 -> Void)
end

def raise(message)
  NativeCallback.putchar(88)
  NativeCallback.putchar(10)
  NativeCallback.exit(0)
end

def install(callback : Proc(Int32, Int32))
  NativeCallback.signal(30, callback)
  NativeCallback.putchar(90)
end
captured = 7_i32
callback = ->(value : Int32) { captured &+ value }
install(callback)
