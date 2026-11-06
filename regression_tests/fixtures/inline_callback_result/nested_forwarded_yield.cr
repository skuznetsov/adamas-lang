lib LibC
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

# Empty-prelude codegen references these exception hooks for ensure cleanup.
# Cases exercise normal completion only; unexpected unwind has a distinct exit.
fun __crystal_personality(version : Int32, actions : Int32, cls : UInt64, ex : Void*, ctx : Void*) : Int32
  LibC._exit(97)
end

fun __crystal_get_exception(ex : Void*) : UInt64
  LibC._exit(97)
end

fun __crystal_raise(ex : Void*) : NoReturn
  LibC._exit(98)
end

fun __crystal_raise_overflow : NoReturn
  LibC._exit(99)
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

class NestedForwardedForallProbe(T)
  @buffer : Pointer(T)
  @remaining : Int32

  def initialize(@buffer : Pointer(T))
    @remaining = 0
  end

  def reference(& : -> F) : F forall F
    begin
      yield
    ensure
      @remaining = 1
    end
  end

  def forward(& : -> F) : F forall F
    reference { yield }
  end

  def read : T
    forward { next @buffer[0] }
  end
end

value = 65
probe = NestedForwardedForallProbe(Int32).new(pointerof(value))
LibC.putchar(probe.read)
LibC.putchar(10)
