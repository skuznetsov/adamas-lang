lib LibC
  fun putchar(value : Int32) : Int32
end
class BaseInput
end
class ChildInput < BaseInput
end
class BindingBox(K, V)
end
class BlockMap
  def transform(& : BaseInput -> Tuple(K, V)) forall K, V
    result = BindingBox(K, V).new
    yield ChildInput.new
    result
  end
end
def accept(value : BindingBox(BaseInput, Bool)) : Int32
  65
end
LibC.putchar(accept(BlockMap.new.transform { |item| {item, true} }))
LibC.putchar(10)
