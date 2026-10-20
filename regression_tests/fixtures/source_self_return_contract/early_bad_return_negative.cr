class EarlyReturnBase
end
class EarlyReturnChild < EarlyReturnBase
end
class EarlyReturnOther
end
class EarlyReturnBase
  def self.make(fail : Bool) : self
    if fail
      return EarlyReturnOther.new
    end
    EarlyReturnChild.new
  end
end
EarlyReturnChild.make(true)
