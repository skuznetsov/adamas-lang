module Marker(T)
end

module DefaultChoice
  extend Marker(Int32)
  def self.byte
    65
  end
end

def choose(value : Marker(Int64) = DefaultChoice, tag : Int32 = 0)
  value.byte
end

choose(tag: 0)
