lib LibC
  fun putchar(c : Int32) : Int32
end
module InstanceProtocol
end
class IncludedInstance
  include InstanceProtocol
end
module Checks
  def self.accept(value : InstanceProtocol) : Int32
    69
  end
end
LibC.putchar(Checks.accept(IncludedInstance.new))
LibC.putchar(10)
