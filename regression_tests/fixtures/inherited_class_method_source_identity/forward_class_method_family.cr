lib LibC
  fun putchar(c : Int32) : Int32
end

class ForwardMethodParent
end

class ForwardMethodChild < ForwardMethodParent
end

# This call precedes the class-method declarations below. Both the child and
# parent later acquire the same method family, and the selected parent overload
# accepts the call.
LibC.putchar(ForwardMethodChild.select(7))
LibC.putchar(10)

class ForwardMethodParent
  def self.select(value : Int32) : Int32
    70
  end
end

class ForwardMethodChild
  def self.select(value : Bool, &block : -> Int32) : Int32
    block.call
  end
end
