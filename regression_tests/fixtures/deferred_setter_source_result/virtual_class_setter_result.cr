lib LibC
  fun putchar(c : Int32) : Int32
end

module DescriptorSystem
  private def blocking=(value)
    read_setting(value)
  end

  private def read_setting(value : Bool)
    42 if value
  end
end

class Descriptor
  include DescriptorSystem

  def apply(value : Bool)
    self.blocking = value
  end
end

class OtherDescriptor < Descriptor
  private def blocking=(value : Bool)
    value
  end
end

def apply(instance : Descriptor, value : Bool)
  instance.apply(value)
end

def start
  run
end

def run
  send_setting
end

def send_setting
  apply(Descriptor.new, true).is_a?(Int32) &&
    apply(Descriptor.new, false).nil? &&
    apply(OtherDescriptor.new, true).is_a?(Bool)
end

LibC.putchar(start ? 65 : 88)
LibC.putchar(10)
