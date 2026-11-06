lib C
  fun putchar(value : Int32) : Int32
end

def explicit_return_void : Void
  C.putchar(82) # R
  return
end

def observe(value : Nil)
  C.putchar(78) # N
end

def observe(value : Int32)
  C.putchar(73) # I
end

observe(explicit_return_void)
C.putchar(10)
