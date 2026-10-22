lib NativeCallback
  fun signal(Int32, (Int32 -> Void)) : (Int32 -> Void)
end

def raise(message)
  1_i32
end

def install(callback : Proc(Int32, Int32))
  NativeCallback.signal(30, callback)
end
captured = 7_i32
callback = ->(value : Int32) { captured &+ value }
install(callback)
