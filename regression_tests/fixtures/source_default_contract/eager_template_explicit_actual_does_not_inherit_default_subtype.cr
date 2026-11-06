module Marker
end

module DefaultChoice
  extend Marker
  def self.only_default
    65
  end
end

module ExplicitChoice
  extend Marker
end

def choose(value : Marker = DefaultChoice)
  value.only_default
end

choose(ExplicitChoice)
