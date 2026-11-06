module Marker
end

module DefaultChoice
  extend Marker
  def self.only_default
    65
  end
end

# Intentionally uncalled. Stock's lazy method-body compilation should not
# treat this default as an actual argument while registering the definition.
def choose(value : Marker = DefaultChoice)
  value.only_default
end
