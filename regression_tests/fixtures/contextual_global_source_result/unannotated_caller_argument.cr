lib C
  fun putchar(Int32) : Int32
  fun getpid : Int32
end

def identity(value)
  value
end

def argument : String
  "wrong owner"
end

class Subject
  def argument : Int32
    66_i32
  end

  def choose_int(flag : Bool) : Int32
    if flag
      yield
    else
      65_i32
    end
  end

  def value : Int32
    choose_int(C.getpid() > 0) { identity(argument) }
  end
end

C.putchar(Subject.new.value)
C.putchar(10_i32)
