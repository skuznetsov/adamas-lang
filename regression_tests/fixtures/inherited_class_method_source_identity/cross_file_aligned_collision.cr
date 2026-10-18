require "./aligned_parent"
require "./aligned_child"

lib LibC
  fun putchar(c : Int32) : Int32
end

LibC.putchar(AlignedSourceChild.build(parent: 1).code)
LibC.putchar(AlignedSourceChild.build(child: 1) &+ 33)

class AlignedSourceReverseParent
  def self.build(parent value : Int32) : self
    new(value)
  end

  def initialize(@value : Int32)
  end

  def code : Int32
    66
  end
end

class AlignedSourceReverseChild < AlignedSourceReverseParent
  def self.build(child value : Int32) : Int32
    67
  end

  def code : Int32
    68
  end
end

LibC.putchar(AlignedSourceReverseChild.build(child: 1) &+ 33)
LibC.putchar(AlignedSourceReverseChild.build(parent: 1).code)
LibC.putchar(10)
