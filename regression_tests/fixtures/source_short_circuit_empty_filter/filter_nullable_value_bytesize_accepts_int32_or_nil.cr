lib C
  fun putchar(value : Int32) : Int32
end

struct Int32
  @[Primitive(:binary)]
  def >(other : Int32) : Bool
  end

  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

class Suffix
  def bytesize : Int32
    1
  end
end

def accepts_int_or_nil(value : Int32?) : Bool
  true
end

def probe(x : Suffix?) : Bool
  accepts_int_or_nil(x && x.bytesize)
end

if probe(nil)
  C.putchar(66)
else
  C.putchar(65)
end
C.putchar(10)
