lib C
  fun putchar(value : Int32) : Int32
end

def effect(value : Int32) : Void
  return
end

class Box(T)
  def effect(value : String) : Int32
    73_i32
  end

  def bad : Int32
    effect(1_i32)
  end
end

C.putchar(Box(Int32).new.bad)
