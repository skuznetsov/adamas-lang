module VirtualSourceFactMarker
  def marker : Int32
    75
  end
end

class VirtualSourceFactInstanceOnly
  include VirtualSourceFactMarker
end

def virtual_source_fact_direct(value : VirtualSourceFactMarker) : Int32
  value.marker
end

virtual_source_fact_direct(VirtualSourceFactInstanceOnly)
