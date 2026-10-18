lib LibC
  fun putchar(c : Int32) : Int32
end

class SameSuffixBlockFirstBase
  def self.build(value : Int32) : self
    new(value)
  end

  def initialize(@value : Int32)
  end

  def code : Int32
    65
  end
end

class SameSuffixBlockFirstChild < SameSuffixBlockFirstBase
  def self.build(value : Int32, &block : -> Int32) : Int32
    block.call
  end

  def code : Int32
    66
  end
end

# Materialize the child's same-argument block overload before selecting the
# inherited no-block factory with the colliding positional signature.
LibC.putchar(SameSuffixBlockFirstChild.build(7) { 67 })
LibC.putchar(SameSuffixBlockFirstChild.build(8).code)
LibC.putchar(10)
