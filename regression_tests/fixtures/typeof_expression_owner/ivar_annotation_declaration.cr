lib Native
  fun putchar(c : Int32) : Int32
end
class Owner
  def initialize(@code : Int32); end
  def run
    value : typeof(@code) = 65
    Native.putchar(value)
  end
end
Owner.new(66).run
