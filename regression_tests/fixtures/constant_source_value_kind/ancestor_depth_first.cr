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
module Deep
  Item = ::Item.new
end
module First
  include Deep
end
module Later
  class Item
  end
end
class Host
  include Later
  include First
  def self.run
    Holder.new(Item).code
  end
end
Native.putchar(Host.run)
Native.putchar(10)
