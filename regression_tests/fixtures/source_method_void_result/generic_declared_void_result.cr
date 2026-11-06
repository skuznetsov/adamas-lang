lib C
  fun putchar(value : Int32) : Int32
end

def generic_void_result(value : T) : Void forall T
  C.putchar(71) # G: generic method effect
  value
end

def observe(value : Nil)
  C.putchar(78) # N: Nil overload
end

def observe(value : Int32)
  C.putchar(73) # I: Int32 overload
end

observe(generic_void_result(23))
C.putchar(10)
