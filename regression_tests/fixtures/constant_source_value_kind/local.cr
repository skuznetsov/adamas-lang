lib Native
  fun putchar(value : Int32) : Int32
end
class Item
  def code : Int32
    65
  end
end
class Holder
  def initialize(@item : Item)
  end
  def code : Int32
    @item.code
  end
end
module App
  Item = ::Item.new
  def self.run
    item = Item
    Holder.new(item).code
  end
end
Native.putchar(App.run)
Native.putchar(10)
