lib LibC
  fun putchar(c : Int32) : Int32
end

class NamedSuffixChildFirstBase
  def self.choose(parent value : Int32) : Int32
    65
  end
end

class NamedSuffixChildFirstChild < NamedSuffixChildFirstBase
  def self.choose(child value : Int32) : Int32
    66
  end
end

# Reverse call order so the local child target exists before the inherited Def
# is materialized under the child's mangled owner.
LibC.putchar(NamedSuffixChildFirstChild.choose(child: 1))
LibC.putchar(NamedSuffixChildFirstChild.choose(parent: 1))
LibC.putchar(10)
