lib C
  fun exit(status : Int32) : NoReturn
end
class NoReturnBase
end
class NoReturnChild < NoReturnBase
end
class NoReturnBase
  def self.make(stop : Bool) : self
    if stop
      C.exit(0)
    else
      self.new
    end
  end
end
value : NoReturnChild = NoReturnChild.make(true)
