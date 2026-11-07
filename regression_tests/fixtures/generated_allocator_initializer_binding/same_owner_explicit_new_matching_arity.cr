lib Native
  fun putchar(value : Int32) : Int32
end

class ExplicitNew
  def self.new(value : Int32) : Int32
    Native.putchar(value)
  end
end

ExplicitNew.new(65)
Native.putchar(10)
