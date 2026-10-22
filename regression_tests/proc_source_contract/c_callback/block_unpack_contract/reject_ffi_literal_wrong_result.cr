lib NativeCallback
  fun bsearch(Void*, Void*, UInt64, UInt64, (Void*, Void* -> Int32)) : Void*
end
value = 7_i32
NativeCallback.bsearch(pointerof(value), pointerof(value), 1_u64, 4_u64, ->(a : Void*, b : Void*) { true })
