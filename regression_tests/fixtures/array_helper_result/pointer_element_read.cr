lib C
  fun putchar(value : Int32) : Int32
end

struct Int32
  @[Primitive(:convert)]
  @[Raises]
  def to_i64 : Int64
  end
end

struct Pointer(T)
  @[Primitive(:pointer_get)]
  def value : T
  end

  @[Primitive(:pointer_add)]
  def +(offset : Int64) : self
  end

  def +(offset : Int)
    self + offset.to_i64
  end

  def [](offset)
    (self + offset).value
  end
end

class PointerElementRead(T)
  @buffer : Pointer(T)

  def initialize(@buffer : Pointer(T))
  end

  def read : T
    @buffer[0]
  end
end

value = 65
C.putchar(PointerElementRead(Int32).new(pointerof(value)).read)
C.putchar(10)
