abstract class Base
end

class A < Base
  def value : Int32
    42
  end
end

class B < Base
end

def probe(x : Base) : Int32?
  x.as?(A).try(&.value)
end

puts probe(A.new) == 42
puts probe(B.new).nil?
