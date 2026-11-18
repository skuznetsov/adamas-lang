lib C
  fun putchar(c : Int32) : Int32
end

def pick(x : Nil.class)
  69
end

def pick(x : Int32)
  70
end

def through(type : Nil.class)
  pick(type || 65)
end

C.putchar(through(Nil))
C.putchar(10)
