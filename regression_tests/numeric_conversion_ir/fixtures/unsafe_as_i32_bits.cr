# Exact minimal methods from the pinned standard library for this
# no-prelude oracle; library files are not modified.
class Object
  def unsafe_as(type : T.class) forall T
    x = self
    pointerof(x).as(T*).value
  end
end
struct Pointer(T)
  @[Primitive(:pointer_get)]
  def value : T
  end
end
lib C
  fun putchar(value : Int32) : Int32
  fun llabs(value : Int64) : Int64
  fun fabsf(value : Float32) : Float32
  fun fabs(value : Float64) : Float64
end
def value : Int32
  1065353216_i32
end
C.putchar(value.unsafe_as(Float32) == 1.0_f32 ? 65 : 66)
