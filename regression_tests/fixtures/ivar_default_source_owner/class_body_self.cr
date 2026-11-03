lib LibC
  fun putchar(value : Int32) : Int32
end
class Parent
  def self.code : Int32; 65; end
  @code : Int32 = self.code
  def code : Int32; @code; end
end
class Subject < Parent
  def self.code : Int32; 66; end
end
LibC.putchar(Subject.new.code)
LibC.putchar(10)
