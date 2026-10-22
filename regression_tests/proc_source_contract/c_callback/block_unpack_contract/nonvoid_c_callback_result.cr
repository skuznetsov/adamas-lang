lib NativeCallback
  fun putchar(Int32) : Int32
  fun exit(Int32) : NoReturn
  fun bsearch(Void*, Void*, UInt64, UInt64, (Void*, Void* -> Int32)) : Void*
end

def raise(message)
  NativeCallback.exit(99)
end

def equal_callback(left, right)
  NativeCallback.putchar(82)
  0_i32
end

def unequal_callback(left, right)
  NativeCallback.putchar(83)
  1_i32
end
value = 7_i32
found = NativeCallback.bsearch(pointerof(value), pointerof(value), 1_u64, 4_u64, ->equal_callback)
if found.address == 0_u64
  NativeCallback.putchar(88)
else
  NativeCallback.putchar(65)
end
missing = NativeCallback.bsearch(pointerof(value), pointerof(value), 1_u64, 4_u64, ->unequal_callback)
if missing.address == 0_u64
  NativeCallback.putchar(66)
else
  NativeCallback.putchar(88)
end
NativeCallback.putchar(10)
