lib Native
  fun putchar(value : Int32) : Int32
end
module Foreign
  class Item
  end
end
def accept(value : Foreign::Item.class) : Int32
  65
end
Native.putchar(accept(Item))
