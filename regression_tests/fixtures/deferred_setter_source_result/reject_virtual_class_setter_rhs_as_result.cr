module DescriptorSystem
  private def blocking=(value)
    42 if value
  end
end

class Descriptor
  include DescriptorSystem

  def apply(value : Bool) : Bool
    self.blocking = value
  end
end

class OtherDescriptor < Descriptor
end

OtherDescriptor.new
Descriptor.new.apply(true)
