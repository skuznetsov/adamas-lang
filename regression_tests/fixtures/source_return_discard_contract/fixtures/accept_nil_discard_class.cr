lib Native
  fun putchar(value : Int32) : Int32
end

class DiscardOwner
  def self.implicit : Nil
    Nil
  end

  def self.explicit : Nil
    return Nil
  end

  def self.number : Nil
    65
  end
end

p = ->(value : Nil) { Native.putchar(65) }
p.call(DiscardOwner.implicit)
p.call(DiscardOwner.explicit)
p.call(DiscardOwner.number)
Native.putchar(10)
