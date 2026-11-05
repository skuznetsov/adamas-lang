lib Native
  fun putchar(value : Int32) : Int32
end
class Host
  lib Values
    CODE = 65
  end
  def self.run
    Values::CODE
  end
end
Native.putchar(Host.run)
Native.putchar(10)
