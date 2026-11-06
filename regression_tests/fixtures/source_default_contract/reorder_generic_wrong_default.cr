module Marker(T)
end

module DefaultChoice
  extend Marker(Int32)
  def self.byte
    65
  end
end

def choose(value : Marker(Int64) = DefaultChoice, **options)
  value.byte
end

choose(tag: 0)
