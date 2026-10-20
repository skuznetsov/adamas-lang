class RuntimeReceiverBase
end
class RuntimeReceiverChild < RuntimeReceiverBase
end
class RuntimeReceiverGrandchild < RuntimeReceiverChild
end
class RuntimeReceiverBase
  def self.make : self
    self.new
  end
end
def observe_runtime_receiver(value : RuntimeReceiverChild) : Int32
  65
end
observe_runtime_receiver(RuntimeReceiverChild.make)
