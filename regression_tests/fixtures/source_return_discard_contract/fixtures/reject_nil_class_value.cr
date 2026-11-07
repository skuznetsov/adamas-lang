lib Native
  fun putchar(value : Int32) : Int32
end

class NilClassOwner
  def self.value : Nil.class
    Nil
  end
end

callback = ->(value : Nil) { Native.putchar(65) }
callback.call(NilClassOwner.value)
Native.putchar(10)
