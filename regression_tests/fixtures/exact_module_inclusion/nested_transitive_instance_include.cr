lib LibC
  fun putchar(c : Int32) : Int32
end
module ReceiverSideSpace
  module Protocol
  end
  module Child
    include Protocol
  end
  class Value
    include Child
  end
end
module Checks
  def self.accept(value : ReceiverSideSpace::Protocol) : Int32
    72
  end
end
LibC.putchar(Checks.accept(ReceiverSideSpace::Value.new))
LibC.putchar(10)
