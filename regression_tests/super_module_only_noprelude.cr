# crystal: no-prelude
# Reducer: class includes module, super in class method goes to module method.
# EXPECT: super_module_only_ok
require "primitives"
require "comparable"
require "string"
require "io"

module M3
  def m_str : String
    "M3"
  end
end

class C3
  include M3

  def m_str : String
    "C3(#{super})"
  end
end

result = C3.new.m_str
if result == "C3(M3)"
  puts "super_module_only_ok"
else
  puts "FAIL"
  puts result
end
