@[Link("c")]
lib VirtualDirectKindOutput
  fun putchar(value : Int32) : Int32
end

module VirtualDirectKindMarker
  def marker : Int32
    75
  end
end

class VirtualDirectKindAlpha
  include VirtualDirectKindMarker
  extend VirtualDirectKindMarker

  def marker : Int32
    73 # I: instance receiver
  end

  def self.marker : Int32
    65 # A: Alpha class-object receiver
  end
end

class VirtualDirectKindBeta
  extend VirtualDirectKindMarker

  def self.marker : Int32
    66 # B: Beta class-object receiver
  end
end

def virtual_direct_kind_pick(value : VirtualDirectKindMarker) : Int32
  VirtualDirectKindOutput.putchar(value.marker)
  0
end

# Alpha and Alpha.new share the ABI carrier; Beta is a second accepted class object.
VirtualDirectKindOutput.putchar(80) # P:
VirtualDirectKindOutput.putchar(58)
virtual_direct_kind_pick(VirtualDirectKindAlpha)
virtual_direct_kind_pick(VirtualDirectKindAlpha.new)
virtual_direct_kind_pick(VirtualDirectKindBeta)
virtual_direct_kind_pick(VirtualDirectKindAlpha.new)
virtual_direct_kind_pick(VirtualDirectKindAlpha)
virtual_direct_kind_pick(VirtualDirectKindAlpha.new)
virtual_direct_kind_pick(VirtualDirectKindBeta)
VirtualDirectKindOutput.putchar(10)
