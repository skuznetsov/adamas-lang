lib Native
  fun putchar(value : Int32) : Int32
end

module VoidBranchOwner
  def self.value(flag : Bool) : Void
    if flag
      Native.putchar(86)
      return
    end
    Native.putchar(87)
  end
end

callback = ->(value : Nil) { Native.putchar(65) }
callback.call(VoidBranchOwner.value(true))
callback.call(VoidBranchOwner.value(false))
Native.putchar(10)
