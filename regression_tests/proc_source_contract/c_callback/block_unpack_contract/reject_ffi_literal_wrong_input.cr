lib NativeCallback
  fun signal(Int32, (Int32 -> Void)) : (Int32 -> Void)
end
NativeCallback.signal(30, ->(value : UInt8) { value })
