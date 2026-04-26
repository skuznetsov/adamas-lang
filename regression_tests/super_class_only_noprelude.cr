# crystal: no-prelude
# Reducer: super in subclass method goes to parent class method (no module).
# EXPECT: super_class_only_ok
require "primitives"
require "comparable"
require "string"
require "io"

class P4
  def p_str : String
    "P4"
  end
end

class C4 < P4
  def p_str : String
    "C4(#{super})"
  end
end

result = C4.new.p_str
if result == "C4(P4)"
  puts "super_class_only_ok"
else
  puts "FAIL"
  puts result
end
