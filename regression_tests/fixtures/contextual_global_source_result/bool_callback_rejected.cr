lib C
  fun getpid : Int32
end

def choose_int(flag : Bool) : Int32
  if flag
    yield
  else
    65_i32
  end
end

choose_int(C.getpid() > 0) { true }
