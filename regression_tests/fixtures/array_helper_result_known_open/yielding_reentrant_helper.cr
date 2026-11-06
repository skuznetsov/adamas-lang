lib C
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
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

class PointerHelperReentrant
  @buffer : Pointer(Int32)
  @depth : Int32

  def initialize(@buffer : Pointer(Int32))
    @depth = 0
  end

  def shift : Int32
    shift { C.exit(7) }
  end

  def shift(&)
    if @depth == 0
      shift_when_not_empty
    else
      yield
    end
  end

  private def shift_when_not_empty
    if @depth == 0
      @depth = 1
      relay { shift_when_not_empty }
    else
      @buffer[0]
    end
  end

  private def relay(&)
    yield
  end
end

value = 65
C.putchar(PointerHelperReentrant.new(pointerof(value)).shift)
C.putchar(10)
