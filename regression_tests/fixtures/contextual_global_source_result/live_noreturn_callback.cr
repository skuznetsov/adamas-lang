lib C
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
  fun exit(status : Int32) : NoReturn
end

def choose_int(flag : Bool) : Int32
  if flag
    yield
  else
    65_i32
  end
end

value = choose_int(C.getpid() > 0) { C.exit(97_i32) }
C.putchar(value)
C.putchar(10_i32)
