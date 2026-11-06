lib C
  fun putchar(value : Int32) : Int32
end

def explicit_nil_result : Nil
  C.putchar(76) # L
  nil
end

def observe(value : Nil)
  C.putchar(78) # N
end

def observe(value : Int32)
  C.putchar(73) # I
end

observe(explicit_nil_result)
C.putchar(10)
