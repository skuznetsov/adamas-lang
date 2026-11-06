@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

module Marker
end

module DefaultChoice
  extend Marker
  def self.byte
    65
  end
end

module ExplicitChoice
  extend Marker
  def self.byte
    66
  end
end

def choose(value : Marker = DefaultChoice, **options)
  value.byte
end

C.putchar(choose(tag: 0))
C.putchar(choose(value: ExplicitChoice, tag: 0))
C.putchar(10)
