class GenericReceiverBase(T)
  def self.make : self
    value : T = 65
    self.new
  end
end
class GenericReceiverChild < GenericReceiverBase(Int32)
end
value : GenericReceiverChild = GenericReceiverChild.make
