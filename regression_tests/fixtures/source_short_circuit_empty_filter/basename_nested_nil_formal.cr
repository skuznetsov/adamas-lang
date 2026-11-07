lib C
  fun putchar(value : Int32) : Int32
end

struct Int32
  @[Primitive(:binary)]
  def >(other : Int32) : Bool
  end

  @[Primitive(:binary)]
  def <(other : Int32) : Bool
  end
end

class Suffix
  def bytesize : Int32
    1
  end
end
def matches(value : Nil) : Bool
  if value && value.bytesize > 0 && value.bytesize < 2
    true
  else
    false
  end
end
if matches(nil)
  C.putchar(66)
else
  C.putchar(65)
end
C.putchar(10)
