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
  def self.accept(item : ::Item.class)
    65
  end
  def self.run
    accept(Item)
  end
end
Native.putchar(App.run)
