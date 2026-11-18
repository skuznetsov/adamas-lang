lib C
  fun putchar(c : Int32) : Int32
end

def with_effect : Nil
  C.putchar(88)
  nil
end

def formal(value : Nil) : Int32
  value || 65
end

def literal : Int32
  nil || 66
end

def call_result : Int32
  with_effect || 67
end

def assigned_result : Int32
  (value = with_effect) || 68
end

C.putchar(formal(nil))
C.putchar(literal)
C.putchar(call_result)
C.putchar(assigned_result)
C.putchar(10)
