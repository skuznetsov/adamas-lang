lib LibC
  fun putchar(value : Int32) : Int32
end
class ParentMacroOwner
  macro choose(value)
    65
  end
end
class ChildMacroOwner < ParentMacroOwner
  def self.choose(value : Int32)
    66
  end
  def self.run
    LibC.putchar(choose(1))
  end
end
ChildMacroOwner.run
LibC.putchar(10)
