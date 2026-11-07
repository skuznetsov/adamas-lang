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

def accepts_nil(value : Nil) : Bool
  true
end

def probe(x : Nil) : Bool
  accepts_nil(x && x.bytesize)
end
if probe(nil)
  C.putchar(66)
else
  C.putchar(65)
end
C.putchar(10)
