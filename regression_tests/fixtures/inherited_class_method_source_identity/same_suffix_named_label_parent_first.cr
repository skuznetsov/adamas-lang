lib LibC
  fun putchar(c : Int32) : Int32
end

class NamedSuffixParentFirstBase
  def self.choose(parent value : Int32) : Int32
    65
  end
end

class NamedSuffixParentFirstChild < NamedSuffixParentFirstBase
  def self.choose(child value : Int32) : Int32
    66
  end
end

# The inherited and child definitions have the same owner-specialized type
# suffix, while their external argument labels select different source Defs.
LibC.putchar(NamedSuffixParentFirstChild.choose(parent: 1))
LibC.putchar(NamedSuffixParentFirstChild.choose(child: 1))
LibC.putchar(10)
