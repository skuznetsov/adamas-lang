lib C
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
  fun exit(status : Int32) : NoReturn
end

class Problem
end

class Subject
  def choose_int(flag : Bool) : Int32
    if flag
      yield
    else
      65_i32
    end
  end

  def raise(error : Problem) : Int32
    66_i32
  end

  def value : Int32
    choose_int(C.getpid() > 0) { raise Problem.new }
  end
end

value = Subject.new.value
C.putchar(value)
C.putchar(10_i32)
