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
def observe(value : Suffix?) : Suffix?
  C.putchar(88)
  value
end

def matches(value : Suffix?) : Bool
  if (seen = observe(value)) && seen.bytesize > 0 && seen.bytesize < 2
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
