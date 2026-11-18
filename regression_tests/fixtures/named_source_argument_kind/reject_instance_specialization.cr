class Receiver
  def self.mark(value : Int32) : Int32
    value
  end
  def mark(value : Bool) : Int32
    65
  end
end
class Forwarder
  def mark(owner, value, flag)
    owner.mark(value)
  end
  def run
    mark(Receiver, 64, flag: false)
    mark(Receiver.new, 64, flag: false)
  end
end
Forwarder.new.run
