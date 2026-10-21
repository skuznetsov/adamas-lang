lib C
  fun signal(sig : Int32, handler : -> Nil) : Pointer(Void)
end
C.signal(2, nil)
