lib Native
  fun putchar(value : Int32) : Int32
end

class ForallOwner
  def self.value(value : T) : T? forall T
    Native.putchar(70)
    return Nil.class
  end
end

callback = ->(value : Nil) { Native.putchar(65) }
callback.call(ForallOwner.value(nil))
Native.putchar(10)
