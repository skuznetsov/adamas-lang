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
  class Item
  end
end
module First
  include Deep
end
module Later
  Item = ::Item.new
end
class Host
  include Later
  include First
  def self.run
    Holder.new(Item).code
  end
end
Host.run
