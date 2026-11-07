lib Native
  fun putchar(value : Int32) : Int32
end

def top_level_value : Nil
  Native.putchar(84)
  return 66
end

class BareTopLevelOwner
  def self.run : Int32
    callback = ->(value : Nil) { Native.putchar(65); 0 }
    callback.call(top_level_value)
    0
  end
end

BareTopLevelOwner.run()
Native.putchar(10)
