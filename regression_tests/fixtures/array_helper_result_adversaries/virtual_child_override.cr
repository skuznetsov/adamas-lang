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

class PointerHelperVirtualBase
  @buffer : Pointer(Int32)
  @remaining : Int32

  def initialize(@buffer : Pointer(Int32), @remaining : Int32)
  end

  def shift : Int32
    shift { C.exit(7) }
  end

  def shift(&)
    if @remaining == 0
      yield
    else
      shift_when_not_empty
    end
  end

  protected def shift_when_not_empty : Int32
    @buffer[0]
  end
end

class PointerHelperVirtualChild < PointerHelperVirtualBase
  def initialize(buffer : Pointer(Int32), remaining : Int32)
    super(buffer, remaining)
  end

  protected def shift_when_not_empty : Int32
    66
  end
end

value = 65
receiver : PointerHelperVirtualBase = PointerHelperVirtualChild.new(pointerof(value), 1)
C.putchar(receiver.shift)
C.putchar(10)
