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
def probe(x : Nil) : Nil
  x && MISSING_SHORT_CIRCUIT_CONSTANT
end
probe(nil)
