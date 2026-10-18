lib LibC
  fun putchar(c : Int32) : Int32
end

class SameSuffixParentFirstBase
  def self.build(value : Int32) : self
    new(value)
  end

  def initialize(@value : Int32)
  end

  def code : Int32
    65
  end
end

class SameSuffixParentFirstChild < SameSuffixParentFirstBase
  def self.build(value : Int32, &block : -> Int32) : Int32
    block.call
  end

  def code : Int32
    66
  end
end

# Reverse the demand order to check that the inherited concrete-self target
# is independent of which colliding signature is registered first.
LibC.putchar(SameSuffixParentFirstChild.build(8).code)
LibC.putchar(SameSuffixParentFirstChild.build(7) { 67 })
LibC.putchar(10)
