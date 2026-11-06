@[Link("c")]
lib VirtualSourceFactOutput
  fun putchar(value : Int32) : Int32
end

module VirtualSourceFactMarker
  def marker : Int32
    75
  end
end

class VirtualSourceFactChoice
  include VirtualSourceFactMarker
  extend VirtualSourceFactMarker

  def marker : Int32
    73
  end

  def self.marker : Int32
    67
  end
end

class VirtualSourceFactBigEndian
  extend VirtualSourceFactMarker

  def self.marker : Int32
    66
  end
end

class VirtualSourceFactLittleEndian
  extend VirtualSourceFactMarker

  def self.marker : Int32
    76
  end
end

class VirtualSourceFactInstanceOnly
  include VirtualSourceFactMarker
end

abstract class VirtualSourceFactRouter
  abstract def dispatch(value : VirtualSourceFactMarker) : Int32
end

class VirtualSourceFactRouterImpl < VirtualSourceFactRouter
  def dispatch(value : VirtualSourceFactMarker) : Int32
    value.marker
  end
end

class VirtualSourceFactInheritedRouter < VirtualSourceFactRouterImpl
end

def virtual_source_fact_class_case(router : VirtualSourceFactRouter) : Int32
  router.dispatch(VirtualSourceFactChoice)
end

def virtual_source_fact_instance_case(router : VirtualSourceFactRouter) : Int32
  router.dispatch(VirtualSourceFactChoice.new)
end

def virtual_source_fact_big_case(router : VirtualSourceFactRouter) : Int32
  router.dispatch(VirtualSourceFactBigEndian)
end

def virtual_source_fact_little_case(router : VirtualSourceFactRouter) : Int32
  router.dispatch(VirtualSourceFactLittleEndian)
end

def virtual_source_fact_direct(value : VirtualSourceFactMarker) : Int32
  value.marker
end

VirtualSourceFactOutput.putchar(virtual_source_fact_class_case(VirtualSourceFactInheritedRouter.new))
VirtualSourceFactOutput.putchar(virtual_source_fact_instance_case(VirtualSourceFactInheritedRouter.new))
VirtualSourceFactOutput.putchar(virtual_source_fact_direct(VirtualSourceFactChoice))
VirtualSourceFactOutput.putchar(virtual_source_fact_direct(VirtualSourceFactChoice.new))
VirtualSourceFactOutput.putchar(virtual_source_fact_big_case(VirtualSourceFactInheritedRouter.new))
VirtualSourceFactOutput.putchar(virtual_source_fact_little_case(VirtualSourceFactInheritedRouter.new))
VirtualSourceFactOutput.putchar(10)
