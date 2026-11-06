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

class PointerHelperTailAfterBranch(T)
  @buffer : Pointer(T)
  @remaining : Int32

  def initialize(@buffer : Pointer(T), @remaining : Int32)
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

  private def shift_when_not_empty : String
    value = @buffer[0]
    @remaining = 0
    value
  end
end

value = 65
PointerHelperTailAfterBranch(Int32).new(pointerof(value), 1).shift
