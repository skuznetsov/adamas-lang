lib Native
  fun putchar(value : Int32) : Int32
end

class VoidOwner
  def self.value : Void
    Native.putchar(86)
    Nil
  end
end

p = ->(value : Nil) { Native.putchar(65) }
p.call(VoidOwner.value)
Native.putchar(10)
