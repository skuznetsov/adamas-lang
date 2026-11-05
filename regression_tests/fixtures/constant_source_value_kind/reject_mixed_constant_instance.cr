lib Native
  fun getpid : Int32
end
class Item
end
VALUE = begin
  if Native.getpid > 0
    Item.new
  else
    Item
  end
end
module App
  def self.accept(value : Item)
    65
  end
end
App.accept(VALUE)
