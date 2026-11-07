lib Native
  fun putchar(value : Int32) : Int32
end

alias NilResultAlias = Nil

class AliasOwner
  def self.value : NilResultAlias
    Native.putchar(76)
    return Nil.class
  end
end

callback = ->(value : Nil) { Native.putchar(65) }
callback.call(AliasOwner.value())
callback.call(AliasOwner.value)
Native.putchar(10)
