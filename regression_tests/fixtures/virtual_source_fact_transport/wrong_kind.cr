module VirtualSourceFactMarker
  def marker : Int32
    75
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

def virtual_source_fact_wrong_kind(router : VirtualSourceFactRouter) : Int32
  router.dispatch(VirtualSourceFactInstanceOnly)
end

virtual_source_fact_wrong_kind(VirtualSourceFactRouterImpl.new)
