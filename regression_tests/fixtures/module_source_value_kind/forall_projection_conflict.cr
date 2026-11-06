module Marker(T); end
class Concrete
  extend Marker(Int32)
end
def conflict(value : Marker(T), witness : T) forall T
end
conflict(Concrete, "wrong")
