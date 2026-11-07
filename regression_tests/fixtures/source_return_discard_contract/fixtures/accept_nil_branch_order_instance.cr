lib Native
  fun putchar(value : Int32) : Int32
end

class BranchOwner
  def value(flag : Bool) : Nil
    if flag
      Native.putchar(73)
      return 65
    end
    Native.putchar(66)
    return Nil.class
  end
end

callback = ->(value : Nil) { Native.putchar(77) }
owner = BranchOwner.new
callback.call(owner.value(true))
callback.call(owner.value(false))
Native.putchar(10)
