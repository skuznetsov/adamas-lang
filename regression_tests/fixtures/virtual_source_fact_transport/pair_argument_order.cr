@[Link("c")]
lib VirtualDirectKindOutput
  fun putchar(value : Int32) : Int32
end

module VirtualDirectKindMarker
  def marker : Int32
    75
  end
end

class VirtualDirectKindChoice
  include VirtualDirectKindMarker
  extend VirtualDirectKindMarker

  def marker : Int32
    73 # I: instance receiver
  end

  def self.marker : Int32
    67 # C: class-object receiver
  end
end

def virtual_direct_kind_pair(first : VirtualDirectKindMarker, second : VirtualDirectKindMarker) : Int32
  VirtualDirectKindOutput.putchar(first.marker)
  VirtualDirectKindOutput.putchar(second.marker)
  0
end

VirtualDirectKindOutput.putchar(65) # A:
VirtualDirectKindOutput.putchar(58)
virtual_direct_kind_pair(VirtualDirectKindChoice, VirtualDirectKindChoice.new)
VirtualDirectKindOutput.putchar(59) # ;
VirtualDirectKindOutput.putchar(66) # B:
VirtualDirectKindOutput.putchar(58)
virtual_direct_kind_pair(VirtualDirectKindChoice.new, VirtualDirectKindChoice)
VirtualDirectKindOutput.putchar(10)
