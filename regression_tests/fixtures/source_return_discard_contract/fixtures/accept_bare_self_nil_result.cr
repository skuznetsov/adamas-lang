lib Native
  fun putchar(value : Int32) : Int32
end

class BareSelfOwner
  def inner : Nil
    Native.putchar(73)
    return 66
  end

  def outer : Int32
    callback = ->(value : Nil) { Native.putchar(65); 0 }
    callback.call(inner)
    0
  end
end

owner = BareSelfOwner.new
owner.outer()
Native.putchar(10)
