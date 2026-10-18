lib LibC
  fun putchar(c : Int32) : Int32
end

class InheritedNamedLabelCollisionBase
  def self.build(parent value : Int32) : self
    new(value)
  end

  def initialize(@value : Int32)
  end

  def code : Int32
    66
  end
end

class InheritedNamedLabelCollisionChild < InheritedNamedLabelCollisionBase
  def self.build(child value : Int32) : Int32
    67
  end

  def code : Int32
    68
  end
end

# The inherited source body is selected by `parent:` and should build the
# concrete child (D). The child's same-typed `child:` overload shares the
# type-only ABI suffix but returns d after the offset below. Call each ordering in a separate class
# family so registration/demand order cannot mask a symbol collision.
LibC.putchar(InheritedNamedLabelCollisionChild.build(parent: 1).code)
LibC.putchar(InheritedNamedLabelCollisionChild.build(child: 1) &+ 33)

class InheritedNamedLabelReverseBase
  def self.build(parent value : Int32) : self
    new(value)
  end

  def initialize(@value : Int32)
  end

  def code : Int32
    66
  end
end

class InheritedNamedLabelReverseChild < InheritedNamedLabelReverseBase
  def self.build(child value : Int32) : Int32
    67
  end

  def code : Int32
    68
  end
end

LibC.putchar(InheritedNamedLabelReverseChild.build(child: 1) &+ 33)
LibC.putchar(InheritedNamedLabelReverseChild.build(parent: 1).code)
LibC.putchar(10)
