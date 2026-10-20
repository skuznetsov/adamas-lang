class WarmReceiverBase
  def self.make : self
    self.new
  end
end
class WarmReceiverFirst < WarmReceiverBase
end
class WarmReceiverSecond < WarmReceiverBase
end
WarmReceiverBase.make
first : WarmReceiverFirst = WarmReceiverFirst.make
second : WarmReceiverSecond = WarmReceiverSecond.make
