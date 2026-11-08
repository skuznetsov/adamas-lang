lib LibC
  fun putchar(value : Int32) : Int32
end
class Base
end
class Child < Base
end
class Item
  def piece : Base
    Child.new
  end
end
class BindingBox(K, V)
  def code
    {% if K == Base %}
      65
    {% elsif K == Child %}
      66
    {% else %}
      67
    {% end %}
  end
end
class BlockMap
  def transform(& : Item -> Tuple(K, V)) forall K, V
    result = BindingBox(K, V).new
    yield Item.new
    result
  end
end
unused_base = Base.new
result = BlockMap.new.transform { |item| {item.piece, item} }
LibC.putchar(result.code)
LibC.putchar(10)
