module Marker(T); end
class Concrete
  extend Marker(Array(String))
end
def needs_int_array(value : Marker(Array(Int32)))
end
needs_int_array(Concrete)
