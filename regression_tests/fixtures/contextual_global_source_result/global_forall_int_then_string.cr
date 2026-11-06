lib C
  fun putchar(value : Int32) : Int32
end

def identity(value : T) : T forall T
  value
end

def classify(value : String) : Int32
  65_i32
end

def classify(value : Int32) : Int32
  73_i32
end

class Box(T)
  def string_then_int : Int32
    classify(identity("s"))
  end

  def int_then_string : Int32
    classify(identity(1_i32))
  end
end

box = Box(Int32).new
C.putchar(box.int_then_string)
C.putchar(box.string_then_int)
C.putchar(10_i32)
