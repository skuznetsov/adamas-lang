class BareReturnBase
end
class BareReturnChild < BareReturnBase
end
class BareReturnBase
  def self.make : self
    return
  end
end
BareReturnChild.make
