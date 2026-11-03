lib LibC
  fun putchar(value : Int32) : Int32
end
class Subject
  def self.code : Int32; 65; end
  @code : Int32 = code
  def initialize(code : Int32); end
  def code : Int32; @code; end
end
LibC.putchar(Subject.new(66).code)
LibC.putchar(10)
