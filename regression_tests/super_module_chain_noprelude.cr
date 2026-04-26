# crystal: no-prelude
# Reducer for STUB CALLED Mid2$Hto_s_super.
# Class with included module + parent class: super in middle should resolve
# to included module first (Crystal MRO).
# EXPECT: super_chain_ok
require "primitives"
require "comparable"
require "string"
require "io"

module Stringifiable
  def stringify : String
    "Stringifiable"
  end
end

class Base2
  def stringify : String
    "Base2"
  end
end

class Mid2 < Base2
  include Stringifiable

  def stringify : String
    "Mid2(#{super})"
  end
end

class Leaf2 < Mid2
  def stringify : String
    "Leaf2(#{super})"
  end
end

result = Leaf2.new.stringify
if result == "Leaf2(Mid2(Stringifiable))"
  puts "super_chain_ok"
else
  puts "FAIL"
  puts result
end
