lib C
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
end

def choose_int(flag : Bool) : Int32
  if flag
    yield
  else
    65_i32
  end
end

def void_probe : Void
  C.putchar(88_i32)
end

choose_int(C.getpid() > 0) { void_probe }
